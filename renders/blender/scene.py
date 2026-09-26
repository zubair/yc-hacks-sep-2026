"""Postcard device scenes for Blender 4.5 LTS (Cycles).

Run through the pipeline:  node render.mjs scenes|anim --data data/<card>.json
Direct:  blender -b --factory-startup -P blender/scene.py -- --manifest out/<id>/manifest.json \
             --mode stills|anim|blend [--shots front,back] [--quality draft|final] [--frames 1-192]

Everything is procedural: the dual-screen foldable is built from device.json,
the screen art comes from the manifest written by `render.mjs screens`, and the
set (travertine, plaster, sunlight through olive leaves) needs no downloads.
"""
import argparse
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

MM = 0.001

# --------------------------------------------------------------------------- args


def parse_args():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument('--manifest', required=True)
    p.add_argument('--mode', default='stills', choices=['stills', 'anim', 'blend'])
    p.add_argument('--shots', default='hero,front,back,sealed,received,sent')
    p.add_argument('--quality', default='final', choices=['draft', 'preview', 'final'])
    p.add_argument('--frames', default=None, help='e.g. 1-192 (anim only)')
    p.add_argument('--transparent', action='store_true', help='film transparent + shadow catcher table')
    return p.parse_args(argv)


QUALITY = {
    'draft': dict(still=(900, 600), anim=(640, 360), samples=24, anim_samples=16),
    'preview': dict(still=(1536, 1024), anim=(960, 540), samples=96, anim_samples=24),
    'final': dict(still=(3072, 2048), anim=(1920, 1080), samples=384, anim_samples=128),
}

# --------------------------------------------------------------------------- scene basics


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def configure_render(res, samples, transparent=False):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    cy = sc.cycles
    cy.device = 'CPU'
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.012
    cy.use_denoising = True
    cy.denoiser = 'OPENIMAGEDENOISE'
    cy.max_bounces = 8
    cy.diffuse_bounces = 3
    cy.glossy_bounces = 4
    cy.transmission_bounces = 6
    cy.caustics_reflective = False
    cy.caustics_refractive = False
    cy.sample_clamp_indirect = 6.0
    cy.blur_glossy = 0.5
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA' if transparent else 'RGB'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'AgX'
    for look in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        try:
            sc.view_settings.look = look
            break
        except TypeError:
            continue
    sc.view_settings.exposure = 0.0
    try:
        sc.render.threads_mode = 'AUTO'
    except AttributeError:
        pass


def add_compositor():
    sc = bpy.context.scene
    sc.use_nodes = True
    nt = sc.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    rl = nt.nodes.new('CompositorNodeRLayers')
    glare = nt.nodes.new('CompositorNodeGlare')
    glare.glare_type = 'FOG_GLOW'
    glare.quality = 'MEDIUM'
    glare.mix = -0.9
    glare.threshold = 0.85
    glare.size = 8
    lens = nt.nodes.new('CompositorNodeLensdist')
    lens.use_fit = True
    for key, val in (('Dispersion', 0.012), ('Distortion', -0.004), ('Distort', -0.004)):
        if key in lens.inputs:
            lens.inputs[key].default_value = val
    out = nt.nodes.new('CompositorNodeComposite')
    nt.links.new(rl.outputs['Image'], glare.inputs['Image'])
    nt.links.new(glare.outputs['Image'], lens.inputs['Image'])
    nt.links.new(lens.outputs['Image'], out.inputs['Image'])
    if 'Alpha' in rl.outputs and 'Alpha' in out.inputs:
        nt.links.new(rl.outputs['Alpha'], out.inputs['Alpha'])


# --------------------------------------------------------------------------- materials


def node_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return m, nt, bsdf


def hexrgb(h, a=1.0):
    h = h.lstrip('#')
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


FINISHES = {
    'champagne': dict(frame='#d9cbb4', back='#cdbfa9', rod='#b7aa95'),
    'titanium': dict(frame='#b9b6b0', back='#a9a6a0', rod='#96938d'),
    'graphite': dict(frame='#55534f', back='#4a4845', rod='#3f3d3a'),
}


def materials(finish):
    f = FINISHES.get(finish, FINISHES['champagne'])
    mats = {}

    m, nt, b = node_mat('Frame')
    b.inputs['Base Color'].default_value = hexrgb(f['frame'])
    b.inputs['Metallic'].default_value = 1.0
    b.inputs['Roughness'].default_value = 0.24
    b.inputs['Anisotropic'].default_value = 0.35
    mats['frame'] = m

    m, nt, b = node_mat('BackGlass')
    b.inputs['Base Color'].default_value = hexrgb(f['back'])
    b.inputs['Roughness'].default_value = 0.42
    b.inputs['Coat Weight'].default_value = 0.4
    b.inputs['Coat Roughness'].default_value = 0.35
    mats['back'] = m

    m, nt, b = node_mat('Bezel')
    b.inputs['Base Color'].default_value = hexrgb('#050506')
    b.inputs['Roughness'].default_value = 0.06
    b.inputs['Coat Weight'].default_value = 1.0
    b.inputs['Coat Roughness'].default_value = 0.02
    mats['bezel'] = m

    m, nt, b = node_mat('Hinge')
    b.inputs['Base Color'].default_value = hexrgb(f['rod'])
    b.inputs['Metallic'].default_value = 1.0
    b.inputs['Roughness'].default_value = 0.18
    mats['rod'] = m

    m, nt, b = node_mat('HingeShadow')
    b.inputs['Base Color'].default_value = hexrgb('#141312')
    b.inputs['Roughness'].default_value = 0.5
    mats['flange'] = m
    return mats


_images = {}


def load_image(path):
    if path not in _images:
        img = bpy.data.images.load(path, check_existing=True)
        img.colorspace_settings.name = 'sRGB'
        _images[path] = img
    return _images[path]


def screen_material(name, paths, emission=0.78):
    """Display: emissive art under a coated, lightly etched glass.

    paths: one image path, or two paths whose mix factor is exposed as
    material['mix'] (animated for the front → sealed swap).
    """
    m, nt, b = node_mat(name)
    uv = nt.nodes.new('ShaderNodeTexCoord')
    texs = []
    for p in (paths if isinstance(paths, (list, tuple)) else [paths]):
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = load_image(p)
        t.interpolation = 'Cubic'
        t.extension = 'EXTEND'
        nt.links.new(uv.outputs['UV'], t.inputs['Vector'])
        texs.append(t)
    color = texs[0].outputs['Color']
    if len(texs) == 2:
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.name = 'Swap'
        mix.inputs['Factor'].default_value = 0.0
        nt.links.new(texs[0].outputs['Color'], mix.inputs['A'])
        nt.links.new(texs[1].outputs['Color'], mix.inputs['B'])
        color = mix.outputs['Result']
    dim = nt.nodes.new('ShaderNodeMix')
    dim.data_type = 'RGBA'
    dim.blend_type = 'MULTIPLY'
    dim.inputs['Factor'].default_value = 1.0
    dim.inputs['B'].default_value = (0.12, 0.12, 0.12, 1)
    nt.links.new(color, dim.inputs['A'])
    nt.links.new(dim.outputs['Result'], b.inputs['Base Color'])
    nt.links.new(color, b.inputs['Emission Color'])
    b.inputs['Emission Strength'].default_value = emission
    b.inputs['Roughness'].default_value = 0.2
    b.inputs['Coat Weight'].default_value = 0.6
    b.inputs['Coat Roughness'].default_value = 0.03
    b.inputs['Coat IOR'].default_value = 1.5
    return m


def travertine():
    m, nt, b = node_mat('Travertine')
    co = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Scale'].default_value = (0.6, 1.6, 0.6)
    nt.links.new(co.outputs['Object'], mp.inputs['Vector'])
    warp = nt.nodes.new('ShaderNodeTexNoise')
    warp.inputs['Scale'].default_value = 2.0
    warp.inputs['Detail'].default_value = 4
    wave = nt.nodes.new('ShaderNodeTexWave')
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'Y'
    wave.inputs['Scale'].default_value = 3.0
    wave.inputs['Distortion'].default_value = 14.0
    wave.inputs['Detail'].default_value = 6
    wave.inputs['Detail Roughness'].default_value = 0.7
    nt.links.new(mp.outputs['Vector'], wave.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.1
    ramp.color_ramp.elements[0].color = hexrgb('#e2d4bd')
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = hexrgb('#eee4d3')
    nt.links.new(wave.outputs['Fac'], ramp.inputs['Fac'])
    # pores: small dark pits, the signature of travertine
    pores = nt.nodes.new('ShaderNodeTexNoise')
    pores.inputs['Scale'].default_value = 160.0
    pores.inputs['Detail'].default_value = 2
    nt.links.new(mp.outputs['Vector'], pores.inputs['Vector'])
    pr = nt.nodes.new('ShaderNodeValToRGB')
    pr.color_ramp.elements[0].position = 0.28
    pr.color_ramp.elements[0].color = (0, 0, 0, 1)
    pr.color_ramp.elements[1].position = 0.34
    pr.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(pores.outputs['Fac'], pr.inputs['Fac'])
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 0.35
    nt.links.new(ramp.outputs['Color'], mix.inputs['A'])
    nt.links.new(pr.outputs['Color'], mix.inputs['B'])
    nt.links.new(mix.outputs['Result'], b.inputs['Base Color'])
    fine = nt.nodes.new('ShaderNodeTexNoise')
    fine.inputs['Scale'].default_value = 900.0
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.25
    bump.inputs['Distance'].default_value = 0.0004
    h = nt.nodes.new('ShaderNodeMath')
    h.operation = 'ADD'
    nt.links.new(fine.outputs['Fac'], h.inputs[0])
    nt.links.new(pr.outputs['Color'], h.inputs[1])
    nt.links.new(h.outputs['Value'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = 0.72
    return m


def plaster():
    m, nt, b = node_mat('Plaster')
    n = nt.nodes.new('ShaderNodeTexNoise')
    n.inputs['Scale'].default_value = 18.0
    n.inputs['Detail'].default_value = 8
    n.inputs['Roughness'].default_value = 0.65
    r = nt.nodes.new('ShaderNodeValToRGB')
    r.color_ramp.elements[0].color = hexrgb('#e2d3bb')
    r.color_ramp.elements[1].color = hexrgb('#f0e6d6')
    nt.links.new(n.outputs['Fac'], r.inputs['Fac'])
    nt.links.new(r.outputs['Color'], b.inputs['Base Color'])
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.35
    nt.links.new(n.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = 0.92
    return m


def leaf_material():
    m, nt, b = node_mat('OliveLeaf')
    b.inputs['Base Color'].default_value = hexrgb('#4f5a36')
    b.inputs['Roughness'].default_value = 0.5
    return m


# --------------------------------------------------------------------------- geometry


def rrect(w, h, r, cx=0.0, cy=0.0, seg=14):
    r = min(r, w / 2, h / 2)
    pts = []
    corners = [(cx + w / 2 - r, cy + h / 2 - r, 0), (cx - w / 2 + r, cy + h / 2 - r, 90),
               (cx - w / 2 + r, cy - h / 2 + r, 180), (cx + w / 2 - r, cy - h / 2 + r, 270)]
    for ox, oy, a0 in corners:
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def new_obj(name, bm, mat, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    if parent:
        ob.parent = parent
    return ob


def slab(name, w, h, t, r, cx, cy, z0, bevel, mat, parent=None, seg=14):
    bm = bmesh.new()
    pts = rrect(w, h, r, cx, cy, seg)
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z0 + t)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    ob = new_obj(name, bm, mat, parent)
    for p in ob.data.polygons:
        p.use_smooth = True
    if bevel > 0:
        mod = ob.modifiers.new('Bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 5
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(40)
        mod.harden_normals = True
        mod.profile = 0.6
    ob.modifiers.new('WN', 'WEIGHTED_NORMAL').keep_sharp = True
    return ob


def screen_plane(name, w, h, r, cx, cy, z, uv_fn, mat, parent=None, facing_up=True):
    bm = bmesh.new()
    pts = rrect(w, h, r, cx, cy, 16)
    vs = [bm.verts.new((x, y, z)) for x, y in pts]
    f = bm.faces.new(vs if facing_up else list(reversed(vs)))
    uvl = bm.loops.layers.uv.new('UVMap')
    for loop in f.loops:
        loop[uvl].uv = uv_fn(loop.vert.co.x, loop.vert.co.y)
    ob = new_obj(name, bm, mat, parent)
    return ob


def cylinder_y(name, radius, length, cx, cz, mat, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=48, radius1=radius, radius2=radius, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(cx, 0, cz))
    ob = new_obj(name, bm, mat, parent)
    for p in ob.data.polygons:
        p.use_smooth = True
    mod = ob.modifiers.new('Bevel', 'BEVEL')
    mod.width = radius * 0.25
    mod.segments = 3
    mod.limit_method = 'ANGLE'
    return ob


class Device:
    """Dual-screen foldable. Root frame: hinge axis along +Y through the origin,
    open-flat screens face +Z, the right pane is fixed and the left pane (which
    carries the cover display on its back) rotates about the pivot.

    fold = 0 → open flat (180°), fold = 180 → closed, cover display facing +Z.
    Cover art reads upright when root -X (towards the hinge) points up.
    """

    def __init__(self, name, spec, mats, tex, emission=0.78):
        p, s, hg = spec['pane'], spec['screen'], spec['hinge']
        W, H, T = p['width'] * MM, p['height'] * MM, p['thickness'] * MM
        R, E = p['cornerRadius'] * MM, p['edgeRadius'] * MM
        ins, sr = s['inset'] * MM, s['cornerRadius'] * MM
        g, zc, rr = hg['halfGap'] * MM, hg['axisLift'] * MM, hg['rodRadius'] * MM
        self.W, self.H, self.T, self.g, self.zc = W, H, T, g, zc
        sw, sh = W - 2 * ins, H - 2 * ins
        glass_t = 0.55 * MM
        lift = 0.06 * MM

        self.root = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(self.root)
        self.pivot = bpy.data.objects.new(name + '.pivot', None)
        bpy.context.collection.objects.link(self.pivot)
        self.pivot.parent = self.root
        self.pivot.location = (0, 0, zc)
        self.pivot.rotation_mode = 'XYZ'

        self.materials = {}
        for side, sign in (('R', 1), ('L', -1)):
            parent = self.root if side == 'R' else self.pivot
            cx = sign * (g + W / 2)
            obs = []
            obs.append(slab(f'{name}.{side}.body', W, H, T, R, cx, 0, -T, E, mats['frame'], parent))
            obs.append(slab(f'{name}.{side}.glass', W - 2 * E * 0.8, H - 2 * E * 0.8, glass_t,
                            R - E * 0.8, cx, 0, -glass_t + lift, 0.22 * MM, mats['bezel'], parent))
            x0 = cx - sw / 2
            inner_uv = (lambda x0_: (lambda x, y: ((x - x0_) / sw, (y + sh / 2) / sh)))(x0)
            key = 'right' if side == 'R' else 'left'
            m_in = screen_material(f'{name}.{key}.screen', tex[key], emission)
            self.materials[key] = m_in
            obs.append(screen_plane(f'{name}.{side}.screen', sw, sh, sr, cx, 0, lift + 0.02 * MM,
                                    inner_uv, m_in, parent))
            if side == 'L':
                obs.append(slab(f'{name}.L.coverglass', W - 2 * E * 0.8, H - 2 * E * 0.8, glass_t,
                                R - E * 0.8, cx, 0, -T - lift, 0.22 * MM, mats['bezel'], parent))
                # landscape art: texture right = +Y, texture up = +X (toward the hinge)
                cover_uv = (lambda x0_: (lambda x, y: ((y + sh / 2) / sh, (x - x0_) / sw)))(x0)
                m_cov = screen_material(f'{name}.cover.screen', tex['cover'], emission)
                self.materials['cover'] = m_cov
                obs.append(screen_plane(f'{name}.L.cover', sw, sh, sr, cx, 0, -T - lift - 0.02 * MM,
                                        cover_uv, m_cov, parent, facing_up=False))
            else:
                obs.append(slab(f'{name}.R.back', W - 2 * E * 0.8, H - 2 * E * 0.8, glass_t,
                                R - E * 0.8, cx, 0, -T - lift, 0.22 * MM, mats['back'], parent))
            # dark hinge flange under the rod so the gap never shows the table
            fl = slab(f'{name}.{side}.flange', g * 1.1, H - 2.2 * R, T * 0.7, 0.4 * MM,
                      sign * g * 0.55, 0, -T * 0.85, 0, mats['flange'], parent, seg=2)
            obs.append(fl)
            if side == 'L':
                for ob in obs:
                    ob.location = (0, 0, -zc)
        self.half = bpy.data.objects.new(name + '.half', None)
        bpy.context.collection.objects.link(self.half)
        self.half.parent = self.root
        self.half.location = (0, 0, zc)
        self.rod = cylinder_y(f'{name}.rod', rr, H - 2.1 * R, 0, -g, mats['rod'], self.half)

    def set_fold(self, degrees, frame=None):
        self.pivot.rotation_euler = (0, math.radians(degrees), 0)
        self.half.rotation_euler = (0, math.radians(-degrees / 2), 0)
        if frame is not None:
            self.pivot.keyframe_insert('rotation_euler', frame=frame)
            self.half.keyframe_insert('rotation_euler', frame=frame)

    def meshes(self):
        out = []

        def walk(o):
            for c in o.children:
                if c.type == 'MESH':
                    out.append(c)
                walk(c)
        walk(self.root)
        return out

    def world_bbox(self):
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for ob in self.meshes():
            ev = ob.evaluated_get(dg)
            for v in ev.data.vertices:
                w = ev.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        return lo, hi

    def place(self, rot, xy=(0.0, 0.0), rest_z=0.0):
        """Orient with a 3x3 rotation, then drop onto the table centred on xy."""
        self.root.matrix_world = rot.to_4x4()
        lo, hi = self.world_bbox()
        c = (lo + hi) / 2
        self.root.location = (xy[0] - c.x, xy[1] - c.y, rest_z - lo.z)
        bpy.context.view_layer.update()


def basis(ex, ey, ez):
    return Matrix((ex, ey, ez)).transposed()


ROT_FLAT_PORTRAIT = Matrix.Identity(3)
# closed, lying flat, cover up, hinge away from camera → landscape art reads upright
ROT_FLAT_LANDSCAPE = Matrix.Rotation(math.radians(-90), 3, 'Z')
# closed, standing on its free edge, cover facing the camera (-Y), hinge on top
ROT_STANDING = basis(Vector((0, 0, -1)), Vector((1, 0, 0)), Vector((0, -1, 0)))


def olive_branch(name, length, seed, mat, leafy=1.0):
    """A flat-ish olive sprig: gently curved stem with alternating lanceolate leaves."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    n = 26
    stem = []
    for i in range(n):
        t = i / (n - 1)
        stem.append(Vector((t * length, math.sin(t * 2.4 + seed) * length * 0.06, 0)))
    for i in range(n - 1):
        a, b_ = stem[i], stem[i + 1]
        d = (b_ - a).normalized()
        nrm = Vector((-d.y, d.x, 0)) * 0.0012 * (1.2 - i / n)
        bm.faces.new([bm.verts.new(a + nrm), bm.verts.new(a - nrm), bm.verts.new(b_ - nrm), bm.verts.new(b_ + nrm)])
    for i in range(2, n):
        if rnd.random() > 0.8 * leafy:
            continue
        base = stem[i]
        side = 1 if i % 2 else -1
        ang = math.radians(rnd.uniform(25, 60)) * side
        L = rnd.uniform(0.05, 0.085)
        Wd = L * rnd.uniform(0.16, 0.22)
        d = (stem[min(i + 1, n - 1)] - stem[i - 1]).normalized()
        dirv = Matrix.Rotation(ang, 3, 'Z') @ d
        perp = Vector((-dirv.y, dirv.x, 0))
        tilt = rnd.uniform(-0.25, 0.25)
        ring = []
        for k in range(12):
            s = k / 11
            width = math.sin(math.pi * s) ** 0.9 * Wd / 2
            p = base + dirv * (L * s)
            ring.append((p + perp * width + Vector((0, 0, tilt * width))))
        for k in range(10, 0, -1):
            s = k / 11
            width = math.sin(math.pi * s) ** 0.9 * Wd / 2
            p = base + dirv * (L * s)
            ring.append((p - perp * width - Vector((0, 0, tilt * width))))
        bm.faces.new([bm.verts.new(v) for v in ring])
    return new_obj(name, bm, mat)


# --------------------------------------------------------------------------- set


class Set:
    def __init__(self, sun_dir, wall=True, transparent=False):
        self.trav = travertine()
        bpy.ops.mesh.primitive_plane_add(size=3.0, location=(0, 0, 0))
        self.table = bpy.context.active_object
        self.table.name = 'Table'
        self.table.data.materials.append(self.trav)
        if transparent:
            self.table.is_shadow_catcher = True
        self.wall = None
        if wall:
            bpy.ops.mesh.primitive_plane_add(size=3.0, location=(0, 0.42, 1.5), rotation=(math.radians(90), 0, 0))
            self.wall = bpy.context.active_object
            self.wall.name = 'Wall'
            self.wall.data.materials.append(plaster())
            if transparent:
                self.wall.hide_render = True

        world = bpy.data.worlds.new('World')
        bpy.context.scene.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes['Background']
        bg.inputs['Color'].default_value = hexrgb('#e9dcc8')
        bg.inputs['Strength'].default_value = 0.26

        d = Vector(sun_dir).normalized()
        sun = bpy.data.lights.new('Sun', 'SUN')
        sun.energy = 4.6
        sun.angle = math.radians(0.7)
        sun.color = (1.0, 0.86, 0.69)
        self.sun = bpy.data.objects.new('Sun', sun)
        bpy.context.collection.objects.link(self.sun)
        self.sun.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        self.sun_dir = d

        fill = bpy.data.lights.new('Fill', 'AREA')
        fill.energy = 9
        fill.size = 1.2
        fill.color = (1.0, 0.93, 0.84)
        fo = bpy.data.objects.new('Fill', fill)
        bpy.context.collection.objects.link(fo)
        fo.location = (-0.2, -0.9, 0.7)
        fo.rotation_euler = (Vector((0, 0, 0.05)) - fo.location).to_track_quat('-Z', 'Y').to_euler()
        self.leaf = leaf_material()

    def gobo(self, target, distance=0.32, spread=0.22, seed=3, count=7):
        """Olive branches between sun and subject: shadow-only."""
        d = self.sun_dir
        centre = Vector(target) - d * distance
        q = d.to_track_quat('-Z', 'Y')
        rnd = random.Random(seed)
        for i in range(count):
            b = olive_branch(f'Gobo.{i}', rnd.uniform(0.3, 0.45), seed * 10 + i, self.leaf, leafy=1.25)
            b.rotation_mode = 'QUATERNION'
            b.rotation_quaternion = q @ Matrix.Rotation(rnd.uniform(0, math.tau), 3, 'Z').to_quaternion()
            off = q @ Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread) * 0.8, rnd.uniform(-0.05, 0.05)))
            b.location = centre + off
            for attr in ('visible_camera', 'visible_diffuse', 'visible_glossy', 'visible_transmission', 'visible_volume_scatter'):
                setattr(b, attr, False)


def camera(loc, target, lens=70, fstop=3.2, focus=None, shift=(0, 0)):
    cd = bpy.data.cameras.new('Camera')
    cd.lens = lens
    cd.sensor_width = 36
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = fstop
    cd.dof.aperture_blades = 7
    cd.shift_x, cd.shift_y = shift
    cam = bpy.data.objects.new('Camera', cd)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cd.dof.focus_distance = ((Vector(focus) if focus else Vector(target)) - Vector(loc)).length
    bpy.context.scene.camera = cam
    return cam


# --------------------------------------------------------------------------- shots


def tex_for(man, cover):
    s = man['screens']
    return {'cover': s[cover], 'left': s['backLeft'], 'right': s['backRight']}


def shot_standing(man, mats, cover, yaw=-9.0, lean=7.0, cam_side=-0.06, seed=3):
    dev = Device('Postcard', man['device'], mats, tex_for(man, cover))
    dev.set_fold(180)
    rot = Matrix.Rotation(math.radians(yaw), 3, 'Z') @ Matrix.Rotation(math.radians(-lean), 3, 'X') @ ROT_STANDING
    dev.place(rot, (0.0, 0.0))
    lo, hi = dev.world_bbox()
    c = (lo + hi) / 2
    st = Set(sun_dir=(0.42, 0.62, -0.66))
    st.gobo(c + Vector((0.02, 0.05, 0.02)), seed=seed)
    # a small travertine block for scale
    blk = slab('Block', 0.07, 0.05, 0.04, 0.004, 0.14, 0.12, 0, 0.003, st.trav)
    blk.rotation_euler = (0, 0, math.radians(18))
    camera((cam_side, -0.46, c.z + 0.075), (c.x, c.y, c.z - 0.004), lens=75, fstop=4.0)
    return dev


def shot_open(man, mats, fold=10.0, seed=5):
    dev = Device('Postcard', man['device'], mats, tex_for(man, 'front'))
    dev.set_fold(fold)
    rot = Matrix.Rotation(math.radians(4), 3, 'Z')
    dev.place(rot, (0.0, 0.0))
    st = Set(sun_dir=(0.5, 0.55, -0.67), wall=False)
    st.gobo((0.0, 0.03, 0.0), seed=seed, count=6)
    blk = slab('Block', 0.08, 0.06, 0.05, 0.004, 0.155, 0.13, 0, 0.003, st.trav)
    blk.rotation_euler = (0, 0, math.radians(-12))
    camera((0.02, -0.25, 0.3), (0.0, 0.004, 0.0), lens=58, fstop=5.6)
    return dev


def shot_hero(man, mats, seed=7):
    back = Device('PostcardOpen', man['device'], mats, tex_for(man, 'front'))
    back.set_fold(24)
    back.place(Matrix.Rotation(math.radians(-10), 3, 'Z'), (0.06, 0.07))
    front = Device('PostcardClosed', man['device'], mats, tex_for(man, 'front'))
    front.set_fold(180)
    front.place(Matrix.Rotation(math.radians(8), 3, 'Z') @ ROT_FLAT_LANDSCAPE, (-0.05, -0.045))
    st = Set(sun_dir=(0.45, 0.6, -0.66))
    st.gobo((0.0, 0.02, 0.02), seed=seed, count=6)
    camera((-0.02, -0.36, 0.2), (0.005, 0.02, 0.012), lens=50, fstop=4.5, focus=(-0.03, -0.03, 0.01))
    return front


def shot_flat(man, mats, cover, seed=9):
    dev = Device('Postcard', man['device'], mats, tex_for(man, cover))
    dev.set_fold(180)
    dev.place(Matrix.Rotation(math.radians(-6), 3, 'Z') @ ROT_FLAT_LANDSCAPE, (0.0, 0.0))
    st = Set(sun_dir=(0.5, 0.5, -0.7), wall=False)
    st.gobo((0.0, 0.0, 0.0), seed=seed, count=5)
    camera((0.0, -0.22, 0.26), (0.0, 0.006, 0.0), lens=60, fstop=5.0)
    return dev


SHOTS = {
    'hero': ('00-hero', lambda m, x: shot_hero(m, x)),
    'front': ('01-front', lambda m, x: shot_standing(m, x, 'front')),
    'back': ('02-back', lambda m, x: shot_open(m, x)),
    'sealed': ('03-sealed', lambda m, x: shot_standing(m, x, 'sealed', yaw=16, cam_side=0.08, seed=11)),
    'sent': ('04-sent', lambda m, x: shot_flat(m, x, 'sent')),
    'received': ('05-received', lambda m, x: shot_flat(m, x, 'received', seed=13)),
}


# --------------------------------------------------------------------------- animation


def build_anim(man, mats, fps=24):
    """Open → write → close → seal, one continuous take (8 s).

      1–24    closed, landscape, front art
      24–48   turns to portrait on the table
      48–84   opens to the back (message + address)
      84–108  hold
      108–138 closes; the cover swaps to the sealed art as it lands (136–140)
      140–164 turns back to landscape
      164–192 hold on sealed
    """
    s = man['screens']
    tex = {'cover': [s['front'], s['sealed']], 'left': s['backLeft'], 'right': s['backRight']}
    dev = Device('Postcard', man['device'], mats, tex)
    sc = bpy.context.scene
    sc.render.fps = fps
    sc.frame_start, sc.frame_end = 1, 192

    turn = bpy.data.objects.new('Turntable', None)
    bpy.context.collection.objects.link(turn)
    dev.root.parent = turn
    off = dev.g + dev.W / 2
    rest = dev.T + 0.06 * MM + 0.55 * MM

    def key(frame, yaw, fold, shift):
        turn.rotation_euler = (0, 0, math.radians(yaw))
        turn.keyframe_insert('rotation_euler', frame=frame)
        dev.root.location = (-shift, 0, rest)
        dev.root.keyframe_insert('location', frame=frame)
        dev.set_fold(fold, frame)

    key(1, -90, 180, off)
    key(24, -90, 180, off)
    key(48, 0, 180, off)
    key(84, 0, 8, 0)
    key(108, 0, 8, 0)
    key(138, 0, 180, off)
    key(140, 0, 180, off)
    key(164, -90, 180, off)
    key(192, -90, 180, off)

    swap = dev.materials['cover'].node_tree.nodes['Swap'].inputs['Factor']
    for f, v in ((136, 0.0), (140, 1.0)):
        swap.default_value = v
        swap.keyframe_insert('default_value', frame=f)

    for ob in [turn, dev.root, dev.pivot, dev.half]:
        if ob.animation_data and ob.animation_data.action:
            for fc in ob.animation_data.action.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = 'BEZIER'
                    kp.easing = 'EASE_IN_OUT'
                    kp.handle_left_type = kp.handle_right_type = 'AUTO_CLAMPED'

    st = Set(sun_dir=(0.5, 0.52, -0.69), wall=False)
    st.gobo((0.0, 0.02, 0.0), seed=5, count=6)
    camera((0.0, -0.3, 0.34), (0.0, 0.008, 0.0), lens=50, fstop=5.6)
    return dev


def encode_mp4(frames_dir, out_path, fps, res):
    """Encode the PNG sequence with Blender's bundled FFmpeg (H.264)."""
    files = sorted(f for f in os.listdir(frames_dir) if f.endswith('.png'))
    if not files:
        return
    sc = bpy.data.scenes.new('Encode')
    bpy.context.window.scene = sc if bpy.context.window else sc
    sc.sequence_editor_create()
    strip = sc.sequence_editor.sequences.new_image('frames', os.path.join(frames_dir, files[0]), 1, 1)
    for f in files[1:]:
        strip.elements.append(f)
    sc.frame_start, sc.frame_end = 1, len(files)
    sc.render.fps = fps
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'FFMPEG'
    sc.render.ffmpeg.format = 'MPEG4'
    sc.render.ffmpeg.codec = 'H264'
    sc.render.ffmpeg.constant_rate_factor = 'HIGH'
    sc.render.ffmpeg.ffmpeg_preset = 'GOOD'
    sc.view_settings.view_transform = 'Standard'
    sc.render.filepath = out_path
    bpy.ops.render.render(animation=True, scene=sc.name)


# --------------------------------------------------------------------------- main


def main():
    a = parse_args()
    man = json.load(open(a.manifest))
    out_dir = os.path.dirname(os.path.abspath(a.manifest))
    q = QUALITY[a.quality]
    finish = man['data']['scene'].get('finish', 'champagne')

    if a.mode in ('stills', 'blend'):
        os.makedirs(os.path.join(out_dir, 'stills'), exist_ok=True)
        for name in [s.strip() for s in a.shots.split(',') if s.strip()]:
            if name not in SHOTS:
                raise SystemExit(f'unknown shot {name}; choose from {", ".join(SHOTS)}')
            reset()
            _images.clear()
            configure_render(q['still'], q['samples'], a.transparent)
            add_compositor()
            mats = materials(finish)
            fname, build = SHOTS[name]
            build(man, mats)
            if a.mode == 'blend':
                bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, 'stills', f'{fname}.blend'))
                continue
            bpy.context.scene.render.filepath = os.path.join(out_dir, 'stills', f'{fname}.png')
            bpy.ops.render.render(write_still=True)
            print(f'still → {bpy.context.scene.render.filepath}', flush=True)
    else:
        reset()
        _images.clear()
        configure_render(q['anim'], q['anim_samples'], a.transparent)
        add_compositor()
        build_anim(man, materials(finish))
        sc = bpy.context.scene
        if a.frames:
            lo, hi = (int(v) for v in a.frames.split('-'))
            sc.frame_start, sc.frame_end = lo, hi
        frames = os.path.join(out_dir, 'anim', 'open-seal')
        os.makedirs(frames, exist_ok=True)
        sc.render.filepath = os.path.join(frames, 'frame_')
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, 'anim', 'open-seal.blend'))
        bpy.ops.render.render(animation=True)
        encode_mp4(frames, os.path.join(out_dir, 'anim', 'open-seal.mp4'), sc.render.fps, q['anim'])
        print(f'anim → {frames}', flush=True)


if __name__ == '__main__':
    main()
