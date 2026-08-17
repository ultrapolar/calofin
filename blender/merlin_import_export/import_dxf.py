# SPDX-License-Identifier: GPL-3.0-or-later
"""Merlin AutoCAD DXF importer (Blender side).

Reads an ASCII DXF via :mod:`dxf_reader` and builds one mesh object per
DXF layer, then arranges the result:

* The object with the most points becomes the parent of the others.
* The parent's origin is set to its centre of mass and snapped to the
  world origin (the whole drawing moves with it).
* The parent is scaled by 0.0254 (AutoCAD inches -> Blender meters);
  the children inherit the scale through the parenting.
"""

import os

import bpy
from bpy.props import BoolProperty, FloatProperty, IntProperty, StringProperty
from bpy_extras.io_utils import ImportHelper
from mathutils import Vector

from . import dxf_reader


class MERLIN_OT_import_dxf(bpy.types.Operator, ImportHelper):
    """Import an AutoCAD DXF as one object per layer, parent them """ \
        """under the densest layer and auto scale/position the drawing"""

    bl_idname = "merlin.import_dxf"
    bl_label = "Merlin Import DXF"
    bl_options = {'REGISTER', 'UNDO', 'PRESET'}

    filename_ext = ".dxf"
    filter_glob: StringProperty(default="*.dxf", options={'HIDDEN'})

    scale: FloatProperty(
        name="Scale",
        description="Scale applied to the parent object (children inherit "
                    "it). 0.0254 converts AutoCAD inches to Blender meters",
        default=0.0254,
        min=1e-9,
        soft_max=1000.0,
        precision=5,
    )
    parent_to_largest: BoolProperty(
        name="Parent to Largest Object",
        description="Make the imported object with the most points the "
                    "parent of all other imported objects",
        default=True,
    )
    center_to_origin: BoolProperty(
        name="Snap to World Origin",
        description="Set the parent object's origin to its centre of mass "
                    "and snap it to the world origin; the rest of the "
                    "drawing keeps its position relative to the parent",
        default=True,
    )
    arc_segments: IntProperty(
        name="Curve Resolution",
        description="Number of straight segments used to approximate a "
                    "full circle (arcs, ellipses and bulges scale with it)",
        default=32,
        min=4,
        max=512,
    )

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False

        box = layout.box()
        box.label(text="Auto Placement", icon='ORIENTATION_GLOBAL')
        box.prop(self, "parent_to_largest")
        box.prop(self, "center_to_origin")
        box.prop(self, "scale")

        box = layout.box()
        box.label(text="Geometry", icon='MESH_DATA')
        box.prop(self, "arc_segments")

    def execute(self, context):
        try:
            with open(self.filepath, "rb") as f:
                raw = f.read()
        except OSError as error:
            self.report({'ERROR'}, "Cannot read file: %s" % error)
            return {'CANCELLED'}

        if raw.startswith(dxf_reader.BINARY_SENTINEL):
            self.report({'ERROR'},
                        "Binary DXF files are not supported; re-save the "
                        "drawing as an ASCII DXF in AutoCAD (SAVEAS)")
            return {'CANCELLED'}

        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("latin-1")

        layers, stats = dxf_reader.parse_dxf(text,
                                             arc_segments=self.arc_segments)
        if not layers:
            skipped = ", ".join(sorted(stats["skipped"])) or "none"
            self.report({'ERROR'},
                        "No importable geometry found in the DXF "
                        "(unsupported entities: %s)" % skipped)
            return {'CANCELLED'}

        if context.mode != 'OBJECT' and bpy.ops.object.mode_set.poll():
            bpy.ops.object.mode_set(mode='OBJECT')

        # One collection per import, named after the file.
        stem = os.path.splitext(os.path.basename(self.filepath))[0]
        collection = bpy.data.collections.new(stem or "DXF")
        context.scene.collection.children.link(collection)

        parent_layer = dxf_reader.pick_parent(layers)
        offset = Vector((0.0, 0.0, 0.0))
        if self.center_to_origin:
            offset = Vector(dxf_reader.center_of_mass(
                layers[parent_layer].verts))

        for selected in context.selected_objects:
            selected.select_set(False)

        objects = {}
        for name, geometry in layers.items():
            mesh = bpy.data.meshes.new(name)
            # Shifting every layer by the parent's centre of mass keeps
            # the drawing aligned while putting all origins (and the
            # parent's centre of mass) at the world origin.
            verts = [(v[0] - offset.x, v[1] - offset.y, v[2] - offset.z)
                     for v in geometry.verts]
            mesh.from_pydata(verts, geometry.edges, geometry.faces)
            mesh.validate()
            mesh.update()
            obj = bpy.data.objects.new(name, mesh)
            collection.objects.link(obj)
            obj.select_set(True)
            objects[name] = obj

        parent_obj = objects[parent_layer]
        if self.parent_to_largest:
            for name, obj in objects.items():
                if obj is not parent_obj:
                    obj.parent = parent_obj
            parent_obj.scale = (self.scale, self.scale, self.scale)
        else:
            for obj in objects.values():
                obj.scale = (self.scale, self.scale, self.scale)

        context.view_layer.objects.active = parent_obj

        total_verts = sum(len(g.verts) for g in layers.values())
        message = ("Imported %d layer object(s), %d point(s); parent '%s' "
                   "(%d points), scale %.4g"
                   % (len(objects), total_verts, parent_layer,
                      len(layers[parent_layer].verts), self.scale))
        if stats["skipped"]:
            message += "; skipped " + ", ".join(
                "%s x%d" % (name, count)
                for name, count in sorted(stats["skipped"].items()))
        self.report({'INFO'}, message)
        return {'FINISHED'}
