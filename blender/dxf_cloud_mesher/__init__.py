# SPDX-License-Identifier: GPL-3.0-or-later
"""DXF Point Cloud Mesher.

Automatically builds geometry from imported DXF point clouds.  DXF
imports often arrive as many separate objects containing nothing but
vertices; this add-on analyses those objects and fills the ones that
qualify:

* Objects whose points vary by no more than a height tolerance on the
  Z axis (4 inches by default) are filled.
* An object exceeding the tolerance is still filled when it is the
  lowest object of the group -- that one is treated as the ground.

Filling avoids triangulation: a single n-gon is created over the
boundary of the point cloud unless that face would overlap vertices
lying inside it, in which case the points are Delaunay-triangulated so
every vertex becomes part of the surface (a TIN).
"""

bl_info = {
    "name": "DXF Point Cloud Mesher",
    "author": "Calofin",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "Object menu > Fill DXF Point Clouds, and "
                "3D Viewport sidebar > DXF Cloud tab",
    "description": "Automatically build meshes from imported DXF "
                   "point-cloud objects",
    "doc_url": "https://github.com/ultrapolar/calofin",
    "category": "Object",
}

if "bpy" in locals():
    import importlib
    importlib.reload(cloud_mesh)
else:
    from . import cloud_mesh

import bpy
import bmesh
from bpy.props import BoolProperty, FloatProperty

# 4 inches in meters (Blender's base length unit).
FOUR_INCHES = 0.1016


def _is_vertex_cloud(mesh):
    return (len(mesh.vertices) >= 3
            and len(mesh.edges) == 0
            and len(mesh.polygons) == 0)


def _build_faces(mesh, kind, data):
    """Create the planned faces on a mesh; returns the number created."""
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        created = 0
        if kind == 'NGON':
            try:
                bm.faces.new([bm.verts[i] for i in data])
                created = 1
            except ValueError:
                pass
        else:
            for tri in data:
                try:
                    bm.faces.new([bm.verts[i] for i in tri])
                    created += 1
                except ValueError:
                    continue
        bm.normal_update()
        bm.to_mesh(mesh)
        mesh.update()
    finally:
        bm.free()
    return created


class OBJECT_OT_dxf_cloud_fill(bpy.types.Operator):
    """Analyse vertex-only DXF point-cloud objects and fill the ones """ \
        """that qualify with faces"""

    bl_idname = "object.dxf_cloud_fill"
    bl_label = "Fill DXF Point Clouds"
    bl_options = {'REGISTER', 'UNDO'}

    height_tolerance: FloatProperty(
        name="Max Height Variation",
        description="An object is filled when its points vary by no more "
                    "than this on the Z axis (default: 4 inches)",
        default=FOUR_INCHES,
        min=0.0,
        soft_max=10.0,
        subtype='DISTANCE',
    )
    fill_lowest: BoolProperty(
        name="Always Fill Lowest Object",
        description="Fill the lowest object of the group (the ground) even "
                    "when its height variation exceeds the tolerance",
        default=True,
    )
    selected_only: BoolProperty(
        name="Selected Objects Only",
        description="Only analyse the selected objects instead of every "
                    "vertex-only mesh in the scene",
        default=False,
    )

    @classmethod
    def poll(cls, context):
        return context.mode == 'OBJECT'

    def execute(self, context):
        if self.selected_only:
            pool = context.selected_objects
        else:
            pool = context.scene.objects
        clouds = [obj for obj in pool
                  if obj.type == 'MESH' and _is_vertex_cloud(obj.data)]
        if not clouds:
            self.report({'ERROR'},
                        "No vertex-only mesh objects (point clouds) found")
            return {'CANCELLED'}

        points_map = {}
        z_bounds = {}
        for obj in clouds:
            matrix = obj.matrix_world
            pts = [matrix @ v.co for v in obj.data.vertices]
            points_map[obj.name] = [(p.x, p.y, p.z) for p in pts]
            zs = [p.z for p in pts]
            z_bounds[obj.name] = (min(zs), max(zs))

        decisions = cloud_mesh.classify_objects(
            z_bounds, self.height_tolerance, fill_lowest=self.fill_lowest)

        filled = ngons = tins = 0
        skipped = []
        print("\n[DXF Point Cloud Mesher] analysing %d object(s):"
              % len(clouds))
        for obj in clouds:
            fill, reason = decisions[obj.name]
            if not fill:
                skipped.append(obj.name)
                print("  - %-32s SKIP  (%s)" % (obj.name, reason))
                continue
            kind, data = cloud_mesh.plan_fill(points_map[obj.name])
            if kind is None:
                skipped.append(obj.name)
                print("  - %-32s SKIP  (%s)" % (obj.name, data))
                continue
            created = _build_faces(obj.data, kind, data)
            if created == 0:
                skipped.append(obj.name)
                print("  - %-32s SKIP  (face creation failed)" % obj.name)
                continue
            filled += 1
            if kind == 'NGON':
                ngons += 1
                print("  - %-32s FILL  n-gon, %d boundary verts (%s)"
                      % (obj.name, len(data), reason))
            else:
                tins += 1
                print("  - %-32s FILL  TIN, %d triangles (%s)"
                      % (obj.name, created, reason))

        message = ("Filled %d of %d point cloud(s): %d n-gon(s), %d TIN(s)"
                   % (filled, len(clouds), ngons, tins))
        if skipped:
            message += "; skipped %d (see console)" % len(skipped)
        self.report({'INFO'} if filled else {'WARNING'}, message)
        return {'FINISHED'}


class VIEW3D_PT_dxf_cloud_mesher(bpy.types.Panel):
    bl_label = "DXF Point Cloud Mesher"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "DXF Cloud"

    def draw(self, context):
        layout = self.layout
        layout.operator(OBJECT_OT_dxf_cloud_fill.bl_idname,
                        icon='OUTLINER_OB_POINTCLOUD')
        column = layout.column(align=True)
        column.label(text="Fills vertex-only objects that stay", icon='INFO')
        column.label(text="within the height tolerance, plus")
        column.label(text="the lowest object (ground).")


def menu_func_object(self, context):
    self.layout.separator()
    self.layout.operator(OBJECT_OT_dxf_cloud_fill.bl_idname,
                         icon='OUTLINER_OB_POINTCLOUD')


classes = (
    OBJECT_OT_dxf_cloud_fill,
    VIEW3D_PT_dxf_cloud_mesher,
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
