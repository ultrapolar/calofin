# SPDX-License-Identifier: GPL-3.0-or-later
"""Export UV Layout to DXF (AutoCAD).

Exports the UV island outlines of the active mesh object as an
AutoCAD-compatible DXF (R12) file:

* Mirrored islands are un-flipped and islands are rotated so shared seam
  edges line up, anchored on a base island (an island that shares edges
  with exactly one other island).
* Only the perimeter of each island is exported; interior edges are
  ignored.
* The drawing is auto-scaled to real-world size using a Freestyle-marked
  edge as the scale reference.
"""

bl_info = {
    "name": "Export UV Layout to DXF (AutoCAD)",
    "author": "Calofin",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "File > Export > UV Layout (.dxf), and UV Editor > UV menu",
    "description": "Export UV island outlines as an AutoCAD-compatible DXF "
                   "with orientation fixing and Freestyle-edge auto scaling",
    "doc_url": "https://github.com/ultrapolar/calofin",
    "category": "Import-Export",
}

if "bpy" in locals():
    import importlib
    importlib.reload(uv_layout)
    importlib.reload(dxf_writer)
else:
    from . import uv_layout
    from . import dxf_writer

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, StringProperty
from bpy_extras.io_utils import ExportHelper
import bmesh


_UNIT_ITEMS = (
    ('MM', "Millimeters", "One DXF unit equals one millimeter"),
    ('CM', "Centimeters", "One DXF unit equals one centimeter"),
    ('M', "Meters", "One DXF unit equals one meter"),
    ('IN', "Inches", "One DXF unit equals one inch"),
)

_UNIT_FACTORS = {
    'MM': 1000.0,
    'CM': 100.0,
    'M': 1.0,
    'IN': 1.0 / 0.0254,
}


class UV_OT_export_layout_dxf(bpy.types.Operator, ExportHelper):
    """Export the active mesh's UV layout as an AutoCAD-compatible DXF file"""

    bl_idname = "uv.export_layout_dxf"
    bl_label = "Export UV Layout to DXF"
    bl_options = {'REGISTER', 'PRESET'}

    filename_ext = ".dxf"
    filter_glob: StringProperty(default="*.dxf", options={'HIDDEN'})

    orient_islands: BoolProperty(
        name="Fix Mirroring & Rotation",
        description="Un-mirror flipped islands (detected from face winding "
                    "versus the face normals) and rotate islands so shared "
                    "seam edges line up with a base island, so every piece "
                    "is oriented as it appears in the 3D Viewport",
        default=True,
    )
    repack: BoolProperty(
        name="Re-pack Islands",
        description="Arrange islands into simple rows after re-orientation "
                    "so they cannot overlap (replaces the original layout "
                    "positions)",
        default=False,
    )
    include_holes: BoolProperty(
        name="Include Holes",
        description="Also export interior boundary loops (holes) of each "
                    "island. Lines inside the island perimeter are never "
                    "exported either way",
        default=True,
    )
    use_freestyle_scale: BoolProperty(
        name="Scale From Freestyle Edge",
        description="Use the edge(s) marked as Freestyle edges as the scale "
                    "reference: the 3D length of the marked edge is compared "
                    "with its length in the UV layout and the resulting "
                    "scale factor is applied to the whole DXF",
        default=True,
    )
    unit: EnumProperty(
        name="Unit",
        description="Real-world drawing unit used for Freestyle-based "
                    "scaling (one DXF unit will equal one of these)",
        items=_UNIT_ITEMS,
        default='MM',
    )
    fallback_scale: FloatProperty(
        name="Manual Scale",
        description="Plain UV-to-DXF multiplier used when Freestyle scaling "
                    "is disabled or no Freestyle-marked edge is found",
        default=1.0,
        min=1e-6,
        soft_max=100000.0,
    )
    layer_per_island: BoolProperty(
        name="Layer Per Island",
        description="Put each island on its own DXF layer (ISLAND_001, "
                    "ISLAND_002, ...) instead of a single UVLAYOUT layer",
        default=False,
    )
    move_to_origin: BoolProperty(
        name="Move to Origin",
        description="Translate the layout so its lower-left corner sits at "
                    "the DXF origin",
        default=True,
    )

    @classmethod
    def poll(cls, context):
        obj = context.active_object
        return obj is not None and obj.type == 'MESH'

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False

        box = layout.box()
        box.label(text="Orientation", icon='ORIENTATION_GIMBAL')
        box.prop(self, "orient_islands")
        box.prop(self, "repack")

        box = layout.box()
        box.label(text="Outlines", icon='MESH_GRID')
        box.prop(self, "include_holes")

        box = layout.box()
        box.label(text="Scale", icon='ARROW_LEFTRIGHT')
        box.prop(self, "use_freestyle_scale")
        box.prop(self, "unit")
        box.prop(self, "fallback_scale")

        box = layout.box()
        box.label(text="Output", icon='CURRENT_FILE')
        box.prop(self, "layer_per_island")
        box.prop(self, "move_to_origin")

    def execute(self, context):
        obj = context.active_object
        if obj is None or obj.type != 'MESH':
            self.report({'ERROR'}, "Active object must be a mesh")
            return {'CANCELLED'}
        if obj.mode == 'EDIT':
            obj.update_from_editmode()
        mesh = obj.data
        if mesh.uv_layers.active is None:
            self.report({'ERROR'}, "Mesh '%s' has no UV map" % mesh.name)
            return {'CANCELLED'}

        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            bm.verts.ensure_lookup_table()
            bm.edges.ensure_lookup_table()
            bm.faces.ensure_lookup_table()
            uv = bm.loops.layers.uv.active

            islands = uv_layout.build_islands(bm, uv)
            if not islands:
                self.report({'ERROR'}, "Mesh has no UV faces to export")
                return {'CANCELLED'}

            base_islands = []
            if self.orient_islands:
                base_islands = uv_layout.orient_islands(islands, uv)

            uv_layout.build_outlines(islands, uv,
                                     include_holes=self.include_holes)
            if self.repack:
                uv_layout.repack_islands(islands)

            scale = self.fallback_scale
            scale_source = "manual scale"
            if self.use_freestyle_scale:
                reference = uv_layout.freestyle_scale_reference(
                    obj, mesh, bm, uv,
                    unit_factor=_UNIT_FACTORS[self.unit],
                    scene_scale=context.scene.unit_settings.scale_length,
                )
                if reference is not None:
                    scale, edge_count = reference
                    scale_source = "%d Freestyle edge(s)" % edge_count
                else:
                    self.report(
                        {'WARNING'},
                        "No usable Freestyle-marked edge found, falling back "
                        "to manual scale %.4f" % self.fallback_scale,
                    )

            layers = []
            outline_count = 0
            if self.layer_per_island:
                for isl in islands:
                    outlines = [
                        [(p.x * scale, p.y * scale) for p in outline]
                        for outline in isl.loops_2d
                    ]
                    if outlines:
                        layers.append((
                            "ISLAND_%03d" % (isl.index + 1),
                            (isl.index % 7) + 1,
                            outlines,
                        ))
                        outline_count += len(outlines)
            else:
                outlines = []
                for isl in islands:
                    outlines.extend(
                        [(p.x * scale, p.y * scale) for p in outline]
                        for outline in isl.loops_2d
                    )
                if outlines:
                    layers.append(("UVLAYOUT", 7, outlines))
                    outline_count = len(outlines)

            if not layers:
                self.report({'ERROR'}, "No island outlines were generated")
                return {'CANCELLED'}

            if self.move_to_origin:
                min_x = min(x for _n, _c, ols in layers
                            for outline in ols for x, _y in outline)
                min_y = min(y for _n, _c, ols in layers
                            for outline in ols for _x, y in outline)
                layers = [
                    (name, color,
                     [[(x - min_x, y - min_y) for x, y in outline]
                      for outline in ols])
                    for name, color, ols in layers
                ]

            dxf_writer.write_dxf(self.filepath, layers)
        finally:
            bm.free()

        message = ("Exported %d outline(s) from %d island(s), "
                   "scale %.6g from %s"
                   % (outline_count, len(islands), scale, scale_source))
        if base_islands:
            message += ("; base island(s): %s"
                        % ", ".join(str(b.index + 1) for b in base_islands))
        self.report({'INFO'}, message)
        return {'FINISHED'}


def menu_func_export(self, context):
    self.layout.operator(UV_OT_export_layout_dxf.bl_idname,
                         text="UV Layout (.dxf)")


def menu_func_uv(self, context):
    self.layout.separator()
    self.layout.operator(UV_OT_export_layout_dxf.bl_idname,
                         text="Export UV Layout to DXF (.dxf)")


classes = (
    UV_OT_export_layout_dxf,
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)
    if hasattr(bpy.types, "IMAGE_MT_uvs"):
        bpy.types.IMAGE_MT_uvs.append(menu_func_uv)


def unregister():
    if hasattr(bpy.types, "IMAGE_MT_uvs"):
        bpy.types.IMAGE_MT_uvs.remove(menu_func_uv)
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
