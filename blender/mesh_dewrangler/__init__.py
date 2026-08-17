# SPDX-License-Identifier: GPL-3.0-or-later
"""Mesh Dewrangler.

Turns wrangled meshes -- triangle soup from scans, imports, booleans or
photogrammetry -- into clean, simplified geometry in one pass:

1. **Dewrangle** (always on stages are toggleable): weld duplicate
   vertices, dissolve degenerate faces/edges, delete loose geometry,
   fill small holes and make all normals point outward.
2. **Denoise**: volume-preserving Taubin smoothing irons out surface
   jitter without deflating the mesh; boundary vertices can be locked
   so open meshes keep their outline.
3. **Simplify**: collapse decimation reduces the triangle count, then
   a planar dissolve merges coplanar triangles into clean quads and
   n-gons.

All three simplification strengths hang off a single **Detail
Preservation** slider: 100 % only cleans the mesh up, lower values
smooth and simplify progressively harder.
"""

bl_info = {
    "name": "Mesh Dewrangler",
    "author": "Calofin",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "Object menu > Dewrangle & Simplify Mesh, and "
                "3D Viewport sidebar > Dewrangle tab",
    "description": "Clean up and simplify messy meshes with a single "
                   "detail-preservation control",
    "doc_url": "https://github.com/ultrapolar/calofin",
    "category": "Mesh",
}

if "bpy" in locals():
    import importlib
    importlib.reload(refine)
else:
    from . import refine

import bpy
import bmesh
from bpy.props import BoolProperty, FloatProperty, IntProperty


def _counts(bm):
    return (len(bm.verts), len(bm.faces))


def _weld_distance(self, bm):
    if not self.auto_weld_distance:
        return self.weld_distance
    if not bm.verts:
        return 0.0
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    return refine.auto_weld_distance(
        (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))


def _delete_loose(bm):
    """Remove wire edges and isolated vertices."""
    loose_edges = [e for e in bm.edges if not e.link_faces]
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context='EDGES')
    loose_verts = [v for v in bm.verts if not v.link_edges]
    if loose_verts:
        bmesh.ops.delete(bm, geom=loose_verts, context='VERTS')


def _smooth(bm, iterations, lock_boundary):
    """Denoise vertex positions with the pure-Python Taubin smoother."""
    bm.verts.ensure_lookup_table()
    index = {v: i for i, v in enumerate(bm.verts)}
    positions = [tuple(v.co) for v in bm.verts]
    neighbours = [[index[e.other_vert(v)] for e in v.link_edges]
                  for v in bm.verts]
    locked = set()
    if lock_boundary:
        locked = {index[v] for v in bm.verts
                  if any(e.is_boundary for e in v.link_edges)}
    smoothed = refine.taubin_smooth(positions, neighbours, iterations,
                                    locked=locked)
    for v, co in zip(bm.verts, smoothed):
        v.co = co


class OBJECT_OT_mesh_dewrangle(bpy.types.Operator):
    """Clean up and simplify the selected meshes: weld, repair, """ \
        """denoise and decimate, keeping as much detail as the """ \
        """preservation slider allows"""

    bl_idname = "object.mesh_dewrangle"
    bl_label = "Dewrangle & Simplify Mesh"
    bl_options = {'REGISTER', 'UNDO'}

    preservation: FloatProperty(
        name="Detail Preservation",
        description="How much of the original detail survives: 100% only "
                    "cleans the mesh up, lower values smooth and simplify "
                    "progressively harder",
        default=0.5,
        min=0.0,
        max=1.0,
        subtype='FACTOR',
    )
    weld: BoolProperty(
        name="Weld Duplicates",
        description="Merge vertices closer together than the weld distance "
                    "(fixes split edges and duplicated geometry)",
        default=True,
    )
    auto_weld_distance: BoolProperty(
        name="Auto Weld Distance",
        description="Derive the weld distance from the mesh size "
                    "(0.01% of the bounding-box diagonal)",
        default=True,
    )
    weld_distance: FloatProperty(
        name="Weld Distance",
        description="Manual merge threshold used when Auto Weld Distance "
                    "is off",
        default=0.0001,
        min=0.0,
        soft_max=1.0,
        precision=5,
        subtype='DISTANCE',
    )
    delete_loose: BoolProperty(
        name="Delete Loose Geometry",
        description="Remove wire edges and vertices not attached to any "
                    "face",
        default=True,
    )
    fill_holes: BoolProperty(
        name="Fill Small Holes",
        description="Close boundary loops with no more sides than the "
                    "hole size limit",
        default=True,
    )
    hole_sides: IntProperty(
        name="Hole Size Limit",
        description="Biggest hole (in number of sides) that gets filled; "
                    "0 fills every hole",
        default=8,
        min=0,
        soft_max=64,
    )
    fix_normals: BoolProperty(
        name="Recalculate Normals",
        description="Make all face normals point consistently outside",
        default=True,
    )
    smooth: BoolProperty(
        name="Denoise (Smooth)",
        description="Iron out surface jitter with volume-preserving "
                    "Taubin smoothing before simplifying",
        default=True,
    )
    decimate: BoolProperty(
        name="Collapse Decimate",
        description="Reduce the triangle count with quadric edge collapse",
        default=True,
    )
    planar: BoolProperty(
        name="Planar Dissolve",
        description="Merge near-coplanar triangles into clean quads and "
                    "n-gons",
        default=True,
    )
    lock_boundary: BoolProperty(
        name="Preserve Boundary",
        description="Keep boundary vertices of open meshes in place while "
                    "denoising, so the outline does not shrink",
        default=True,
    )

    @classmethod
    def poll(cls, context):
        return context.mode == 'OBJECT'

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.prop(self, "preservation")

        box = layout.box()
        box.label(text="Dewrangle", icon='BRUSH_DATA')
        box.prop(self, "weld")
        sub = box.column()
        sub.active = self.weld
        sub.prop(self, "auto_weld_distance")
        row = sub.column()
        row.active = not self.auto_weld_distance
        row.prop(self, "weld_distance")
        box.prop(self, "delete_loose")
        box.prop(self, "fill_holes")
        sub = box.column()
        sub.active = self.fill_holes
        sub.prop(self, "hole_sides")
        box.prop(self, "fix_normals")

        box = layout.box()
        box.label(text="Simplify", icon='MOD_DECIM')
        box.prop(self, "smooth")
        sub = box.column()
        sub.active = self.smooth
        sub.prop(self, "lock_boundary")
        box.prop(self, "decimate")
        box.prop(self, "planar")

    def _process(self, mesh, settings):
        """Run the pipeline on one mesh; returns (before, after) counts."""
        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            before = _counts(bm)

            threshold = _weld_distance(self, bm)
            if self.weld and threshold > 0.0:
                bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=threshold)
                bmesh.ops.dissolve_degenerate(bm, dist=threshold,
                                              edges=bm.edges)
            if self.delete_loose:
                _delete_loose(bm)
            if self.fill_holes:
                bmesh.ops.holes_fill(bm, edges=bm.edges,
                                     sides=self.hole_sides)
            if self.fix_normals and bm.faces:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

            if self.smooth and settings["smooth_iterations"] > 0:
                _smooth(bm, settings["smooth_iterations"],
                        self.lock_boundary)

            if self.decimate and settings["collapse_ratio"] < 1.0 and bm.faces:
                # Collapse decimation works on triangles; the planar
                # dissolve afterwards rebuilds quads/n-gons anyway.
                bmesh.ops.triangulate(bm, faces=bm.faces)
                bmesh.ops.decimate(bm, ratio=settings["collapse_ratio"])
            if self.planar and settings["dissolve_angle"] > 0.0:
                bmesh.ops.dissolve_limit(
                    bm,
                    angle_limit=settings["dissolve_angle"],
                    use_dissolve_boundaries=False,
                    verts=bm.verts,
                    edges=bm.edges,
                )
                bmesh.ops.dissolve_degenerate(bm, dist=max(threshold, 1e-9),
                                              edges=bm.edges)

            after = _counts(bm)
            bm.to_mesh(mesh)
            mesh.update()
        finally:
            bm.free()
        return before, after

    def execute(self, context):
        objects = [obj for obj in context.selected_objects
                   if obj.type == 'MESH']
        if not objects:
            self.report({'ERROR'}, "Select at least one mesh object")
            return {'CANCELLED'}

        settings = refine.derive_settings(self.preservation)
        totals = [0, 0]
        print("\n[Mesh Dewrangler] preservation %.0f%% -> %d smoothing "
              "pass(es), collapse to %.1f%% of triangles, planar dissolve "
              "%.1f degrees"
              % (self.preservation * 100.0,
                 settings["smooth_iterations"],
                 settings["collapse_ratio"] * 100.0,
                 settings["dissolve_angle"] * 180.0 / 3.141592653589793))
        for obj in objects:
            before, after = self._process(obj.data, settings)
            totals[0] += before[1]
            totals[1] += after[1]
            print("  - %-32s %d verts / %d faces  ->  %d verts / %d faces"
                  % (obj.name, before[0], before[1], after[0], after[1]))

        percent = refine.reduction_percent(totals[0], totals[1])
        self.report({'INFO'},
                    "Dewrangled %d object(s): %d -> %d faces (-%.1f%%)"
                    % (len(objects), totals[0], totals[1], percent))
        return {'FINISHED'}


class VIEW3D_PT_mesh_dewrangler(bpy.types.Panel):
    bl_label = "Mesh Dewrangler"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Dewrangle"

    def draw(self, context):
        layout = self.layout
        layout.operator(OBJECT_OT_mesh_dewrangle.bl_idname,
                        icon='MOD_SMOOTH')
        column = layout.column(align=True)
        column.label(text="Cleans and simplifies the selected", icon='INFO')
        column.label(text="meshes; the preservation slider")
        column.label(text="sets how much detail survives.")


def menu_func_object(self, context):
    self.layout.separator()
    self.layout.operator(OBJECT_OT_mesh_dewrangle.bl_idname,
                         icon='MOD_SMOOTH')


classes = (
    OBJECT_OT_mesh_dewrangle,
    VIEW3D_PT_mesh_dewrangler,
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.VIEW3D_MT_object.append(menu_func_object)


def unregister():
    bpy.types.VIEW3D_MT_object.remove(menu_func_object)
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
