# SPDX-License-Identifier: GPL-3.0-or-later
"""Merlin Import/Export.

Single package bundling the Merlin CAD round-trip for Blender:

* **Import** -- reads an AutoCAD ASCII DXF, creates one mesh object per
  DXF layer, parents everything under the layer object with the most
  points, sets that parent's origin to its centre of mass snapped to
  the world origin, and scales it by 0.0254 (inches -> meters).
* **Export** -- the existing "Export CAD Mesh to DXF (Layered)"
  exporter: mesh edges split by material into FLOOR / WALL / STEPS
  objects with WIRES / BASELINE / SLICE / PERIMETER layers by edge
  marking.

The two live behind one UI: *File > Merlin Import/Export* opens a
dialog with an Import and an Export button.  The operators are also
reachable from the regular File > Import and File > Export menus.
"""

bl_info = {
    "name": "Merlin Import/Export",
    "author": "Calofin",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "File > Merlin Import/Export, File > Import > "
                "Merlin AutoCAD DXF, File > Export > Merlin CAD Mesh",
    "description": "Import AutoCAD DXFs (auto scale/position, one object "
                   "per layer) and export mesh edges as a layered AutoCAD "
                   "DXF",
    "doc_url": "https://github.com/ultrapolar/calofin",
    "category": "Import-Export",
}

if "bpy" in locals():
    import importlib
    importlib.reload(dxf_reader)
    importlib.reload(import_dxf)
    importlib.reload(mesh_layers)
    importlib.reload(dxf_writer)
    importlib.reload(export_cad_mesh)
else:
    from . import dxf_reader
    from . import import_dxf
    from . import mesh_layers
    from . import dxf_writer
    from . import export_cad_mesh

import bpy


class MERLIN_OT_import_export_dialog(bpy.types.Operator):
    """Open the Merlin Import/Export dialog"""

    bl_idname = "merlin.import_export_dialog"
    bl_label = "Merlin Import/Export"

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(
            self, width=300, confirm_text="Close")

    def draw(self, context):
        layout = self.layout
        layout.operator_context = 'INVOKE_DEFAULT'

        column = layout.column()
        column.scale_y = 1.5
        column.operator(import_dxf.MERLIN_OT_import_dxf.bl_idname,
                        text="Import", icon='IMPORT')
        column.operator(export_cad_mesh.MERLIN_OT_export_cad_mesh_dxf.bl_idname,
                        text="Export", icon='EXPORT')

        hints = layout.column(align=True)
        hints.label(text="Import: AutoCAD DXF, one object per layer,",
                    icon='INFO')
        hints.label(text="auto parented, centered and scaled.")
        hints.separator()
        hints.label(text="Export: mesh edges as a layered CAD DXF",
                    icon='INFO')
        hints.label(text="(FLOOR/WALL/STEPS objects by material).")
        if not export_cad_mesh.MERLIN_OT_export_cad_mesh_dxf.poll(context):
            hints.label(text="Export needs a mesh object in the scene.",
                        icon='ERROR')

    def execute(self, context):
        return {'FINISHED'}


def menu_func_file(self, context):
    self.layout.separator()
    self.layout.operator(MERLIN_OT_import_export_dialog.bl_idname,
                         text="Merlin Import/Export", icon='ARROW_LEFTRIGHT')


def menu_func_import(self, context):
    self.layout.operator(import_dxf.MERLIN_OT_import_dxf.bl_idname,
                         text="Merlin AutoCAD DXF (.dxf)")


def menu_func_export(self, context):
    self.layout.operator(export_cad_mesh.MERLIN_OT_export_cad_mesh_dxf.bl_idname,
                         text="Merlin CAD Mesh (.dxf)")


classes = (
    import_dxf.MERLIN_OT_import_dxf,
    export_cad_mesh.MERLIN_OT_export_cad_mesh_dxf,
    MERLIN_OT_import_export_dialog,
)


def register():
    for cls in classes:
        bpy.utils.register_class(cls)
    bpy.types.TOPBAR_MT_file.append(menu_func_file)
    bpy.types.TOPBAR_MT_file_import.append(menu_func_import)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
    bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)
    bpy.types.TOPBAR_MT_file.remove(menu_func_file)
    for cls in reversed(classes):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
