# SPDX-License-Identifier: GPL-3.0-or-later
"""Export CAD Mesh to DXF (Layered).

Exports mesh edges as an AutoCAD-compatible DXF (R12) formatted for a
layer-based CAD design process:

* Faces are split by material into export groups -- materials named
  *floor*, *wall* and *step* map to FLOOR / WALL / STEPS -- and each
  group becomes its own AutoCAD object (a BLOCK + INSERT).
* Every edge is routed onto a fixed layer by its Blender marking:
  unmarked edges go to WIRES, seams to BASELINE, Freestyle-marked edges
  to SLICE and sharp edges to PERIMETER.
"""

bl_info = {
    "name": "Export CAD Mesh to DXF (Layered)",
    "author": "Calofin",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "File > Export > CAD Mesh (.dxf)",
    "description": "Export mesh edges as an AutoCAD DXF split into "
                   "FLOOR/WALL/STEPS objects with WIRES, BASELINE, SLICE "
                   "and PERIMETER layers from edge markings",
    "doc_url": "https://github.com/ultrapolar/calofin",
    "category": "Import-Export",
}

if "bpy" in locals():
    import importlib
    importlib.reload(mesh_layers)
    importlib.reload(dxf_writer)
else:
    from . import mesh_layers
    from . import dxf_writer

import bpy
from bpy.props import BoolProperty, EnumProperty, StringProperty
from bpy_extras.io_utils import ExportHelper


_UNIT_ITEMS = (
    ('IN', "Inches", "One DXF unit equals one inch"),
    ('MM', "Millimeters", "One DXF unit equals one millimeter"),
    ('CM', "Centimeters", "One DXF unit equals one centimeter"),
    ('M', "Meters", "One DXF unit equals one meter"),
)

_UNIT_FACTORS = {
    'IN': 1.0 / 0.0254,
    'MM': 1000.0,
    'CM': 100.0,
    'M': 1.0,
}


def _collect_edge_records(obj, mesh, scale):
    """Build (a, b, seam, freestyle, sharp, groups) records for a mesh."""
    matrix = obj.matrix_world

    slot_groups = [
        mesh_layers.group_for_material(
            material.name if material is not None else None)
        for material in mesh.materials
    ]

    edge_groups = {}
    for poly in mesh.polygons:
        if 0 <= poly.material_index < len(slot_groups):
            group = slot_groups[poly.material_index]
        else:
            group = mesh_layers.GROUP_UNGROUPED
        for loop_index in poly.loop_indices:
            edge_index = mesh.loops[loop_index].edge_index
            edge_groups.setdefault(edge_index, set()).add(group)

    freestyle = mesh_layers.freestyle_edge_indices(mesh)

    coords = [(matrix @ v.co) * scale for v in mesh.vertices]
    records = []
    for edge in mesh.edges:
        a = coords[edge.vertices[0]]
        b = coords[edge.vertices[1]]
        records.append((
            (a.x, a.y, a.z),
            (b.x, b.y, b.z),
            edge.use_seam,
            edge.index in freestyle,
            edge.use_edge_sharp,
            edge_groups.get(edge.index, {mesh_layers.GROUP_UNGROUPED}),
        ))
    return records


class EXPORT_OT_cad_mesh_dxf(bpy.types.Operator, ExportHelper):
    """Export mesh edges as a layered AutoCAD DXF (FLOOR/WALL/STEPS """ \
        """objects; WIRES, BASELINE, SLICE and PERIMETER layers)"""

    bl_idname = "export_mesh.cad_layers_dxf"
    bl_label = "Export CAD Mesh to DXF"
    bl_options = {'REGISTER', 'PRESET'}

    filename_ext = ".dxf"
    filter_glob: StringProperty(default="*.dxf", options={'HIDDEN'})

    selected_only: BoolProperty(
        name="Selected Objects Only",
        description="Export only the selected mesh objects instead of "
                    "every mesh object in the scene",
        default=True,
    )
    apply_modifiers: BoolProperty(
        name="Apply Modifiers",
        description="Export the evaluated mesh (modifiers applied) "
                    "instead of the raw mesh data",
        default=True,
    )
    use_blocks: BoolProperty(
        name="Group as Objects (Blocks)",
        description="Write each group (FLOOR, WALL, STEPS, ...) as a "
                    "DXF block with one insert so it arrives in AutoCAD "
                    "as a single selectable object. Disable to write "
                    "plain lines on the marking layers only",
        default=True,
    )
    unit: EnumProperty(
        name="Unit",
        description="Real-world unit of one DXF unit "
                    "(scene unit scale is taken into account)",
        items=_UNIT_ITEMS,
        default='IN',
    )

    @classmethod
    def poll(cls, context):
        return any(obj.type == 'MESH' for obj in context.scene.objects)

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False

        box = layout.box()
        box.label(text="Input", icon='MESH_DATA')
        box.prop(self, "selected_only")
        box.prop(self, "apply_modifiers")

        box = layout.box()
        box.label(text="Output", icon='CURRENT_FILE')
        box.prop(self, "use_blocks")
        box.prop(self, "unit")

    def execute(self, context):
        if self.selected_only:
            pool = [obj for obj in context.selected_objects
                    if obj.type == 'MESH']
            if not pool and context.active_object is not None \
                    and context.active_object.type == 'MESH':
                pool = [context.active_object]
        else:
            pool = [obj for obj in context.scene.objects
                    if obj.type == 'MESH']
        if not pool:
            self.report({'ERROR'}, "No mesh objects to export")
            return {'CANCELLED'}

        scale = (_UNIT_FACTORS[self.unit]
                 * context.scene.unit_settings.scale_length)

        depsgraph = None
        if self.apply_modifiers:
            depsgraph = context.evaluated_depsgraph_get()

        records = []
        for obj in pool:
            if obj.mode == 'EDIT':
                obj.update_from_editmode()
            if depsgraph is not None:
                obj_eval = obj.evaluated_get(depsgraph)
                mesh = obj_eval.to_mesh()
                try:
                    records.extend(
                        _collect_edge_records(obj_eval, mesh, scale))
                finally:
                    obj_eval.to_mesh_clear()
            else:
                records.extend(
                    _collect_edge_records(obj, obj.data, scale))

        if not records:
            self.report({'ERROR'}, "Selected meshes contain no edges")
            return {'CANCELLED'}

        grouped = mesh_layers.collect_segments(records)
        dxf_writer.write_dxf(
            self.filepath,
            layers=mesh_layers.LAYERS,
            groups=list(grouped.items()),
            use_blocks=self.use_blocks,
        )

        layer_counts = {}
        for by_layer in grouped.values():
            for layer, segments in by_layer.items():
                layer_counts[layer] = layer_counts.get(layer, 0) + len(segments)
        summary_groups = ", ".join(
            "%s (%d)" % (group, sum(len(s) for s in by_layer.values()))
            for group, by_layer in grouped.items())
        summary_layers = ", ".join(
            "%s %d" % (name, layer_counts[name])
            for name, _color in mesh_layers.LAYERS if name in layer_counts)
        message = ("Exported %d edge(s) from %d object(s): %s; layers: %s"
                   % (len(records), len(pool), summary_groups, summary_layers))
        unknown = [g for g in grouped
                   if g not in mesh_layers.KNOWN_GROUPS]
        if unknown:
            self.report(
                {'WARNING'},
                "%s. Groups outside FLOOR/WALL/STEPS were exported too: %s "
                "(materials not named floor/wall/step, or faces without "
                "material)" % (message, ", ".join(unknown)))
        else:
            self.report({'INFO'}, message)
        return {'FINISHED'}


def menu_func_export(self, context):
    self.layout.operator(EXPORT_OT_cad_mesh_dxf.bl_idname,
                         text="CAD Mesh (.dxf)")


classes = (
    EXPORT_OT_cad_mesh_dxf,
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
