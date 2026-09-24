"""Original fleet presentation models, beauty renders and runtime GLBs.

Run: Blender --background --python tools/blender/build_presentation_assets.py -- [ids]
The recognition builder supplies class silhouettes; this pass adds materials, deck fittings,
markings, curved glazing and weapon-family models. These are illustrative game art, not
engineering models. No external meshes, textures or military technical drawings are used.
GLBs are centred and normalised to a ten-unit longest dimension for the inspection stage.
"""
import importlib.util
import json
import math
import os
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
module = importlib.util.spec_from_file_location("recognition", HERE / "build_platform_art.py")
b = importlib.util.module_from_spec(module)
module.loader.exec_module(b)
ROOT = HERE.parent.parent
ART = ROOT / "assets/platforms"
WEAPONS = ROOT / "assets/weapons"
MODELS = ROOT / "assets/models"
MATS = {}
THUMBS_ONLY = False


def mat(name, color, roughness=.58, metallic=.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    shader = m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    m.diffuse_color = (*color, 1)
    MATS[name] = m
    return m


def palette():
    mat("naval_paint", (.39, .46, .50))
    mat("deck_non_skid", (.075, .10, .12), .93)
    mat("flight_deck", (.075, .09, .105), .90)
    mat("antifouling", (.21, .045, .037), .8)
    mat("boot_topping", (.019, .028, .032), .7)
    mat("array_face", (.52, .57, .55), .72)
    mat("radome", (.74, .77, .70), .56)
    mat("glazing", (.014, .065, .092), .15, .64)
    mat("canopy_gold", (.17, .20, .18), .13, .70)
    mat("rubber", (.018, .024, .029), .84)
    mat("titanium", (.20, .24, .28), .30, .80)
    mat("bronze", (.35, .20, .065), .35, .72)
    mat("marking_white", (.79, .82, .79), .7)
    mat("marking_yellow", (.69, .43, .055), .70)
    mat("hazard_red", (.47, .06, .045), .62)
    mat("airframe", (.30, .36, .40), .58)
    mat("airframe_light", (.49, .56, .59), .62)
    mat("airframe_blue", (.23, .33, .39), .70)
    mat("missile_body", (.66, .70, .68), .50)
    mat("seeker", (.21, .24, .23), .27, .40)


def paint(obj, name):
    obj.data.materials.clear()
    obj.data.materials.append(MATS[name])
    return obj


def bounds(obj):
    vs = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return (Vector(tuple(min(v[i] for v in vs) for i in range(3))),
            Vector(tuple(max(v[i] for v in vs) for i in range(3))))


def rod(a, c, radius, material="naval_paint", name="railing"):
    a, c = Vector(a), Vector(c)
    o = b.cylinder(0, 0, 0, (c-a).length, radius, segs=8, name=name)
    o.location = a
    o.rotation_euler = (c-a).to_track_quat("Z", "Y").to_euler()
    return paint(o, material)


def stripe(a, c, width=.2, material="marking_white"):
    a, c = Vector(a), Vector(c)
    side = Vector((-(c-a).y, (c-a).x, 0)).normalized() * width / 2
    return paint(b.add_mesh("deck_marking", [a-side, c-side, c+side, a+side], [(0,1,2,3)]), material)


def circle(x, y, z, radius, width=.18, material="marking_white"):
    for i in range(64):
        a, c = math.tau*i/64, math.tau*(i+1)/64
        stripe((x+radius*math.cos(a), y+radius*math.sin(a), z),
               (x+radius*math.cos(c), y+radius*math.sin(c), z), width, material)


def burke(spec):
    """More slender sheer, usable aft flight deck, individual VLS hatches and array faces."""
    L = spec["length_m"]
    B = 20.4
    fa, ff = 4.2, 7.2
    x = lambda t: L*(t-.5)
    d = lambda t: b.deck_z(fa, ff, t)
    b.hull(L, B, 7.0, fa, ff, stations=48, transom=.75, fullness=.52, flare=1.025)
    b.prism(x(.48), x(.67), -8.3, 8.3, d(.56), d(.56)+7, .65, "deckhouse")
    b.prism(x(.54), x(.66), -6.5, 6.5, d(.56)+7, d(.56)+10.2, .35, "bridge")
    b.prism(x(.34), x(.48), -7.0, 7.0, d(.40), d(.40)+5.5, .6, "midhouse")
    b.hangar(x(.16), x(.33), B, d(.24), 5.7)
    b.funnel(x(.45), 0, d(.4)+5.5, 4.8, 4.5, 5.5, -.5)
    b.funnel(x(.36), 0, d(.3)+5.7, 4.8, 4.3, 5.3, -.5)
    b.mast(x(.57), 0, d(.56)+10.2, 32.8, .36, 8)
    b.mast(x(.36), 0, d(.3)+10.5, 24.5, .28, 4.5)
    for sign in (-1, 1):
        b.radar_face(x(.635), sign*8.28, d(.56)+1.5, 4.3 if "iii" in spec["id"] else 3.9, 4.3, sign)
        b.radar_face(x(.49), sign*8.28, d(.56)+1.5, 4.3, 4.3, sign)
        b.boat(x(.45), sign*9.3, d(.43))
    # Fore and aft banks occupy 32 and 64 cells respectively; hatch geometry is visual.
    b.vls(x(.685), x(.747), 0, d(.71)+.4, 8.4, rows=4)
    b.vls(x(.25), x(.33), 0, d(.24)+5.9, 10.6, rows=4)
    b.prism(x(.785)-2.8, x(.785)+2.6, -2.2, 2.2, d(.79), d(.79)+3.2, .8, "turret")
    b.cylinder(0, d(.79)+2.2, x(.785)+2.0, x(.785)+9.2, .22, segs=16, axis="x", name="barrel")
    b.ciws(x(.64), 0, d(.56)+10.2)
    b.ciws(x(.19), 0, d(.24)+5.7)
    for t in (.33,.39):
        b.dome(x(t), 0, d(.24)+8.8, 1.05)
    # Communications aerials, life-raft packs, bollards and navigation radars give scale.
    for t in (.18,.24,.40,.49,.56):
        for sign in (-1,1):
            b.cylinder(x(t),sign*7.2,d(.24)+5.8,d(.24)+6.6,.52,16,'liferaft')
    for t in (.05,.12,.82,.90):
        beam=7 if t<.5 else (4 if t<.85 else 2.5)
        for sign in (-1,1):
            for dx in (-.35,.35):
                b.cylinder(x(t)+dx,sign*beam,d(t),d(t)+.65,.22,12,'bollard')
    for yy in (-3.6,-2.4,2.4,3.6):
        b.mast(x(.59),yy,d(.56)+10.2,d(.56)+16.0,.07)
    b.cbox(x(.57),0,29.5,1.1,5.8,.35,'navigation_array')
    b.cbox(x(.36),0,23.0,.8,4.2,.30,'navigation_array')


def lightning(spec):
    L=spec['length_m']
    carrier=spec['id'].endswith('f35c')
    b.fuselage(L,L*.066,nose=.31,tail=.30,segs=32,taper=.55)
    span=13.1 if carrier else 10.7
    for s in (-1,1):
        b.plate([(L*.13,s*.78),(-L*.27,s*.88),(-L*.245,s*span/2),(-L*.17,s*span/2)],-.055,.055,'wing')
        b.plate([(L*.27,s*.62),(L*.10,s*1.37),(-L*.31,s*1.45),(-L*.4,s*.7)],-.40,.35,'chines')
        b.plate([(-L*.26,s*.60),(-L*.49,s*.63),(-L*.49,s*L*.22),(-L*.39,s*L*.23)],-.05,.05,'stab')
        b.fin(-L*.27,L*.19,L*.06,L*.145,L*.12,y=s*L*.075,cant=-s*.44,thickness=.09)
        b.prism(-L*.15,L*.13,s*1.10-.29,s*1.10+.29,-.55,.35,.1,'intake_fairing')
        paint(b.box(L*.13+.001,L*.13+.02,s*1.10-.21,s*1.10+.21,-.46,.22,'intake_mouth'),'rubber')
    b.engine_pod(-L*.505,-L*.18,0,-.20,L*.047)
    b.cbox(L*.19,0,L*.062,L*.18,L*.075,L*.054,'canopy')
    if not carrier:
        b.cylinder(0,0,L*.067,L*.068,L*.056,32,'lift_fan_door')


def surface_details(spec):
    bpy.context.view_layer.update()
    for o in list(b._objects):
        name = o.name.split(".")[0]
        lo, hi = bounds(o)
        dim = hi-lo
        if name == "hull":
            for m in ("deck_non_skid", "antifouling", "boot_topping"):
                o.data.materials.append(MATS[m])
            for p in o.data.polygons:
                if p.center.z < -.7:
                    p.material_index = 2
                elif p.center.z < .65:
                    p.material_index = 3
                elif p.normal.z > .6:
                    p.material_index = 1
                p.use_smooth = p.center.z < 0 or abs(p.normal.z) < .5
            # Parallel guardrails follow each deck station, including the narrowing bow.
            rings = len(o.data.vertices)//12
            for sign, idx in ((1,5),(-1,7)):
                points = []
                for i in range(rings):
                    v = o.data.vertices[i*12+idx].co.copy()
                    v.y *= .99
                    points.append(v)
                for i in range(len(points)-1):
                    for z in (.52, 1.03):
                        rod(points[i]+Vector((0,0,z)), points[i+1]+Vector((0,0,z)), .035)
                    if i%2 == 0:
                        rod(points[i], points[i]+Vector((0,0,1.05)), .045)
        elif name in ("bridge", "fwd_block", "accommodation", "island", "forward_island", "aft_island"):
            # Continuous glazing band divided into bridge windows on each outboard face.
            for sign in (-1,1):
                yy = hi.y+.015 if sign>0 else lo.y-.015
                for i in range(max(3,int(dim.x/1.6))):
                    xx = lo.x+.8+i*(dim.x-1.6)/max(1,int(dim.x/1.6))
                    paint(b.box(xx, xx+.92, yy-.02, yy+.02, hi.z-1.38, hi.z-.50, "bridge_window"), "glazing")
            for i in range(max(3,int(dim.y/1.5))):
                yy = lo.y+.65+i*(dim.y-1.3)/max(1,int(dim.y/1.5))
                paint(b.box(hi.x+.015, hi.x+.04, yy, yy+.8, hi.z-1.38, hi.z-.50, "bridge_window"), "glazing")
        elif name == "vls":
            nx, ny = max(2,round(dim.x/1.5)), max(2,round(dim.y/1.35))
            for ix in range(nx):
                for iy in range(ny):
                    x0, y0 = lo.x+ix*dim.x/nx+.09, lo.y+iy*dim.y/ny+.09
                    paint(b.box(x0,x0+dim.x/nx-.18,y0,y0+dim.y/ny-.18,hi.z+.01,hi.z+.06,"cell_hatch"),"array_face")
                    paint(b.box(x0+.12,x0+.35,y0+.12,y0+.25,hi.z+.065,hi.z+.095,"hatch_latch"),"rubber")
        elif name == "funnel":
            paint(b.box(lo.x+.3,hi.x-.3,lo.y+.3,hi.y-.3,hi.z-.01,hi.z+.05,"stack_exhaust"),"rubber")
        elif name == "hangar":
            for sign in (-1,1):
                cy = sign*dim.y*.23
                paint(b.box(lo.x-.04,lo.x-.02,cy-dim.y*.18,cy+dim.y*.18,lo.z+.2,hi.z-.8,"hangar_door"),"deck_non_skid")
                for i in range(7):
                    stripe((lo.x-.05,cy-dim.y*.18,lo.z+.4+i*.65), (lo.x-.05,cy+dim.y*.18,lo.z+.4+i*.65), .04,"naval_paint")
        elif name in ("deckhouse","midhouse","aft_house"):
            for sign in (-1,1):
                yy = hi.y if sign>0 else lo.y
                for i in range(3):
                    xx = lo.x+dim.x*.18+i*1.0
                    paint(b.box(xx,xx+.54,yy-.035,yy+.035,lo.z+1.0,lo.z+2.6,"vent"),"deck_non_skid")
    # A clear, correctly sized aft landing area on helo-capable combatants.
    L = spec["length_m"]
    hulls = [o for o in b._objects if o.name.split('.')[0]=='hull']
    if hulls and 'carrier' not in spec['category'] and 'merchant' not in spec['category']:
        h = hulls[0]
        lo,hi = bounds(h)
        if any(o.name.startswith("hangar") for o in b._objects):
            x = -L*.428
            v = min(h.data.vertices,key=lambda v:abs(v.co.x-x)+abs(v.co.y)).co
            z = max(v.z, max(p.co.z for p in h.data.vertices if abs(p.co.x-x)<L*.04))+.12
            r = min((hi.y-lo.y)*.30,L*.050)
            # Raised non-skid pad avoids cambered hull occluding the painted markings.
            paint(b.box(x-r*1.1,x+r*1.1,-r*1.1,r*1.1,z-.1,z,"landing_pad"),"deck_non_skid")
            circle(x,0,z+.018,r)
            for yy in (-r*.28,r*.28):
                stripe((x-r*.38,yy,z+.025),(x+r*.38,yy,z+.025),.24)
            stripe((x, -r*.28,z+.026),(x,r*.28,z+.026),.24)
            stripe((x-r*.9,0,z+.027),(x+r*.9,0,z+.027),.09,"marking_yellow")


def carrier_details(spec):
    decks = [o for o in b._objects if o.name.split('.')[0] in ('flight_deck','straight_flight_deck','deck')]
    if not decks:
        return
    deck = max(decks,key=lambda o:len(o.data.vertices))
    lo,hi = bounds(deck)
    L, B = spec['length_m'],hi.y-lo.y
    z = hi.z+.055
    sid = spec['id']
    is_stovl = sid in ('rn_cvf_queen_elizabeth','usn_lha_america','esp_lhd_juan_carlos_i')
    helo_only = sid == 'fra_lhd_mistral'
    # Angled recovery lane and paired forward catapult tracks on CATOBAR decks.
    angle = 0 if is_stovl or helo_only else .13
    if not helo_only:
        for sign in (-1,1):
            stripe((-L*.43,-B*.14+sign*B*.12,z),(L*.25,L*.68*angle-B*.14+sign*B*.12,z),.38)
        for i in range(18):
            xx = -L*.42+i*L*.035
            yy = -B*.14+(xx+L*.43)*angle
            stripe((xx,yy,z+.01),(xx+L*.018,yy+L*.018*angle,z+.01),.38,"marking_yellow")
    if not is_stovl and not helo_only:
        for y in (-B*.16,B*.15):
            stripe((L*.06,y,z),(L*.43,y,z),.20)
            stripe((L*.06,y+.85,z),(L*.43,y+.85,z),.10,"marking_yellow")
        for i in range(4):
            xx = -L*.30+i*L*.018
            stripe((xx,-B*.28,z+.02),(xx,B*.10,z+.02),.1,"titanium")
    else:
        for t in ((-.35,-.18,.0,.18,.35) if helo_only else (-.3,-.12,.07)):
            circle(L*t,B*.04,z+.02,5.5 if helo_only else 6.5,.25)
    # Four small, parked airframes bring the scale of the deck into view.
    parked_positions = [(-L*.33,B*.31),(-L*.23,B*.31),(L*.17,B*.30),(L*.27,B*.30)]
    if sid in ('esp_lhd_juan_carlos_i','fra_cvn_charles_de_gaulle'):
        parked_positions = [(-L*.31,B*.28),(L*.15,B*.28)]
    if helo_only:
        parked_positions = [(-L*.33,B*.04),(-L*.02,B*.04),(L*.28,B*.04)]
    for xx,yy in parked_positions:
        before = len(b._objects)
        if helo_only:b.build_panther(13.7)
        elif sid == 'fra_cvn_charles_de_gaulle':b.build_rafale(15.3)
        elif sid == 'esp_lhd_juan_carlos_i':b.build_harrier(14.1)
        else:b.build_lightning(15.7,not is_stovl)
        parked = b._objects[before:]
        for o in parked:
            o.location += Vector((xx,yy,z+1.15))
            paint(o,"airframe_light" if not o.name.startswith('canopy') else 'glazing')


def curved_canopy(o):
    lo,hi = bounds(o)
    c,dim = (lo+hi)*.5,hi-lo
    b._objects.remove(o)
    bpy.data.objects.remove(o,do_unlink=True)
    # A low, curved canopy with a dark frame, replacing the recognition model's box.
    prof=[]
    for i in range(25):
        t=i/24
        prof.append((c.x-dim.x*.52+dim.x*1.04*t,max(.015,math.sin(math.pi*t)**.65)))
    o=b.revolve(prof,segs=32,name="curved_canopy")
    for v in o.data.vertices:
        v.co.y=v.co.y*dim.y*.66+c.y
        v.co.z=v.co.z*dim.z*.75+c.z
    paint(o,"canopy_gold")
    for p in o.data.polygons:p.use_smooth=True


def aircraft_details(spec):
    bpy.context.view_layer.update()
    for o in list(b._objects):
        name=o.name.split('.')[0]
        lo,hi=bounds(o)
        if name=='canopy':
            curved_canopy(o)
        elif name=='engine':
            r=(hi.y-lo.y)*.5
            paint(b.cylinder((lo.y+hi.y)*.5,(lo.z+hi.z)*.5,lo.x-.025,lo.x+.08,r*.84,32,'nozzle','x'),"titanium")
            paint(b.cylinder((lo.y+hi.y)*.5,(lo.z+hi.z)*.5,lo.x-.032,lo.x-.026,r*.65,32,'exhaust','x'),"rubber")
            if hi.x>0:
                paint(b.cylinder((lo.y+hi.y)*.5,(lo.z+hi.z)*.5,hi.x+.01,hi.x+.025,r*.85,32,'intake','x'),"rubber")
        elif name=='wing':
            # Trailing-edge control surfaces are picked out without outlining every polygon.
            verts=sorted(o.data.vertices,key=lambda v:v.co.z)
            for v in o.data.vertices:
                if abs(v.co.y)>(hi.y-lo.y)*.6:
                    for p in o.data.polygons:
                        if p.normal.z>.5 and spec['nation']=='RUS':
                            o.data.materials.append(MATS['airframe_blue'])
                            p.material_index=1
                    break
            # Thin control-surface seams and low-visibility registration bars.
            if len(o.data.vertices)==8:
                pts=[v.co for v in o.data.vertices[4:]]
                for i in range(4):
                    a,c=pts[i],pts[(i+1)%4]
                    center=sum(pts,Vector())/4
                    aa,cc=a.lerp(center,.07),c.lerp(center,.07)
                    aa.z+=.012;cc.z+=.012
                    stripe(aa,cc,.012,'array_face')
            if hi.y-lo.y>3:
                yy=(lo.y+hi.y)*.64
                xx=(lo.x+hi.x)*.5
                stripe((xx-.22,yy,hi.z+.02),(xx+.22,yy,hi.z+.02),.11,'array_face')
    # Airframe banding and a nose radome are separate material zones on the smooth fuselage.
    for o in b._objects:
        if o.name.split('.')[0]=='fuselage':
            o.data.materials.append(MATS['array_face'])
            for p in o.data.polygons:
                if p.center.x>spec['length_m']*.33:p.material_index=1


def finish_materials(spec):
    domain=spec['domain']
    for o in list(b._objects):
        name=o.name.split('.')[0]
        m='naval_paint'
        if domain=='subsurface':m='rubber'
        elif domain=='air':m='airframe_blue' if spec['nation']=='RUS' else 'airframe'
        if name in ('deck','flight_deck','straight_flight_deck','ski_jump','vls','runway','landing_pad'):m='flight_deck'
        elif 'array' in name or name=='vls_line':m='array_face'
        elif name=='dome':m='radome'
        elif name in ('rotor','tail_rotor','prop','propeller','intake_mouth','tire'):m='rubber'
        elif name in ('canopy','window'):m='glazing'
        elif name in ('engine','barrel','pumpjet','vector_nozzle'):m='titanium'
        elif name=='propeller' and domain=='subsurface':m='bronze'
        paint(o,m)
        if name in ('hull','fuselage','engine','dome','pressure_hull','mast','cyl','tube','pumpjet'):
            for p in o.data.polygons:p.use_smooth=True
        if name not in ('hull','fuselage','pressure_hull'):
            bevel=o.modifiers.new('edge highlights','BEVEL')
            bevel.width=.008 if domain=='air' else .06
            bevel.segments=2
    if domain=='surface':
        surface_details(spec)
        if 'carrier' in spec['category'] or spec['id'] in ('usn_lha_america','esp_lhd_juan_carlos_i','fra_lhd_mistral'):
            carrier_details(spec)
    elif domain=='air':aircraft_details(spec)


def weapon_specs():
    result={}
    for path in sorted((ROOT/'data/weapons').glob('*.tres')):
        txt=path.read_text()
        fields=dict(re.findall(r'^(\w+) = "([^"]*)"',txt,re.M))
        result[fields['id']]=fields
    return result


def weapon_model(w):
    wid,kind=w['id'],w.get('type','asm')
    if kind in ('ciws','gun'):
        if wid=='phalanx_ciws':
            b.cylinder(0,0,-1,0,1.0,32,'base')
            b.cbox(0,0,.8,1.8,1.5,1.6,'mount')
            b.cylinder(-.35,0,1.2,2.7,.72,32,'radome')
            cap=b.revolve([(0,.72),(.25,.69),(.48,.54),(.65,.30),(.72,.001)],32,'radome')
            cap.rotation_euler=(0,-math.pi/2,0)
            cap.location=(-.35,0,2.7)
            b.cbox(.1,.93,.65,1.4,.55,1.35,'feed_housing')
            for i in range(6):
                a=i*math.tau/6
                b.cylinder(math.cos(a)*.13,.45+math.sin(a)*.13,.5,2.35,.043,12,'barrel','x')
        else:
            b.cylinder(0,0,-.4,.0,1.6,32,'base')
            b.prism(-2,1.5,-1.5,1.5,0,2.8,.65,'turret')
            for offset in (-.45, .45) if wid=='ak130_gun' else (0,):
                b.cylinder(offset,1.6,1.,7.3,.16,24,'barrel','x')
        for o in b._objects:
            paint(o,'radome' if o.name.startswith(('dome','radome')) else ('titanium' if o.name.startswith('barrel') else 'naval_paint'))
            if o.name.startswith(('base','radome','barrel')):
                for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
        return
    torp=kind=='torpedo' and wid not in ('rgm_139_vla','rastrub_asw')
    slim=wid.startswith(('aim','r77','r73','mica','sea_ceptor','ram','meteor','asraam','iris_t','mistral'))
    L=3.5 if slim else 6.5
    R=.09 if slim else .19
    if kind=='asm':L,R=5.0,.24
    if 'oniks' in wid or 'kh32' in wid:L,R=8.5,.36
    if wid=='essm_family':L,R=3.65,.127
    if wid=='sea_ceptor':L,R=3.2,.083
    if wid=='aim9x_family':L,R=3.0,.064
    if wid=='aim120_family':L,R=3.65,.089
    if wid=='rgm_139_vla':L,R=4.5,.21
    if wid=='rastrub_asw':L,R=7.2,.32
    if wid.startswith('aster'):L,R=4.9,.18
    if torp:L,R=(2.7,.16) if any(s in wid for s in ('54','sting','mu90','apr3')) else (6.0,.267)
    # External proportions only. These shapes carry no internal engineering detail.
    dimensions={
        'meteor_aam':(3.65,.089), 'asraam_aam':(2.9,.083), 'iris_t_aam':(2.94,.064),
        'agm65e_maverick':(2.49,.152), 'rbs15f':(4.35,.25), 'kh31a':(4.70,.18),
        'f21_torpedo':(6.0,.267), 'torpedo62':(6.0,.267), 'torpedo47':(2.85,.20),
        'mistral_naval':(1.86,.045), 'otomat_mk2':(4.46,.23), 'shtil1':(5.18,.18),
    }
    L,R=dimensions.get(wid,(L,R))
    if 'lrasm' in wid or 'nsm' in wid:
        pts=[(-L/2,-R*.7),(-L/2+L*.12,-R),(L*.25,-R),(L/2,0),(L*.25,R),(-L/2+L*.12,R),(-L/2,R*.7)]
        b.plate(pts,-R*.7,R*.7,'stealth_body')
    else:
        profile=[(-L/2,.04),(-L/2+L*.09,R),(L*.26,R)]
        for i in range(1,13):
            t=i/12
            profile.append((L*.26+L*.24*t, R*max(.005,math.cos(t*math.pi/2)**(.45 if torp else 1.1))))
        b.revolve(profile,32,'weapon_body')
    if not torp:
        for angle in (0,math.pi/2,math.pi,math.pi*1.5):
            span=R*3 if slim else R*3.4
            o=b.plate([(-L*.42,0),(-L*.26,0),(-L*.39,span),(-L*.48,span)],-.023,.023,'tail_fin')
            o.rotation_euler.x=angle
            if kind=='asm' or (kind=='sam' and not slim):
                o=b.plate([(-L*.15,0),(L*.08,0),(-L*.05,span*1.2),(-L*.22,span*1.2)],-.018,.018,'mid_fin')
                o.rotation_euler.x=angle
        if wid.startswith('sm3') or wid.startswith('aster') or wid=='rgm_139_vla':
            # Distinct booster/upper-stage proportions, without modelling internal systems.
            b.cylinder(0,0,-L*.48,-L*.15,R*1.2,32,'booster','x')
        if wid in ('tomahawk_block_v','kalibr_asm'):
            for sign in (-1,1):
                b.plate([(-L*.15,0),(0,0),(-L*.05,sign*L*.25),(-L*.18,sign*L*.25)],-.015,.015,'cruise_wing')
        if wid=='r77_family':
            # The recognisable lattice tails are an external visual cue.
            for angle in (0,math.pi/2,math.pi,math.pi*1.5):
                for j in range(4):
                    o=b.box(-L*.43+j*L*.018,-L*.42+j*L*.018,R*.9,R*3.7,-.013,.013,'lattice_tail')
                    o.rotation_euler.x=angle
        if 'oniks' in wid:
            b.cylinder(0,0,L*.37,L*.49,R*.65,32,'ramjet_intake','x')
        if wid in ('meteor_aam','kh31a'):
            # Meteor's paired intakes and Kh-31's four prominent ducts remain recognisable.
            for angle in ((math.pi*.25,math.pi*1.25) if wid=='meteor_aam' else (0,math.pi/2,math.pi,math.pi*1.5)):
                yy,zz=R*1.14*math.cos(angle),R*1.14*math.sin(angle)
                b.cylinder(yy,zz,-L*.31,L*.15,R*.48,20,'ramjet_duct','x')
                b.cylinder(yy,zz,L*.15,L*.152,R*.35,20,'ramjet_intake','x')
        if wid=='otomat_mk2':
            for sign in (-1,1):
                b.plate([(-L*.10,0),(L*.04,0),(-L*.02,sign*L*.25),(-L*.15,sign*L*.25)],-.025,.025,'cruise_wing')
            b.cbox(-L*.07,0,-R*1.18,L*.31,R*.9,R*.7,'intake_fairing')
        if wid=='iris_t_aam':
            for angle in (0,math.pi/2,math.pi,math.pi*1.5):
                o=b.plate([(-L*.20,0),(L*.10,0),(L*.03,R*2.9),(-L*.25,R*2.9)],-.012,.012,'mid_fin')
                o.rotation_euler.x=angle
    else:
        for i in range(7):
            a=math.tau*i/7
            o=b.plate([(-L*.50,0),(-L*.48,R*1.5),(-L*.46,R*1.7),(-L*.45,0)],-.018,.018,'propeller')
            o.rotation_euler.x=a
        for a in (0,math.pi/2,math.pi,math.pi*1.5):
            o=b.plate([(-L*.38,0),(-L*.27,0),(-L*.31,R*1.7),(-L*.40,R*1.7)],-.026,.026,'tail_fin')
            o.rotation_euler.x=a
    for o in b._objects:
        name=o.name.split('.')[0]
        paint(o,'rubber' if name=='ramjet_intake' else ('bronze' if name=='propeller' else ('airframe' if name=='stealth_body' else 'missile_body')))
        if name=='weapon_body':
            for m in ('seeker','marking_yellow','titanium'):
                o.data.materials.append(MATS[m])
            for p in o.data.polygons:
                p.use_smooth=True
                if p.center.x>L*.27:p.material_index=1
                elif -L*.38<p.center.x<-L*.29:p.material_index=2
                elif p.center.x<-L*.4:p.material_index=3
        elif name in ('tail_fin','mid_fin','cruise_wing','lattice_tail'):
            paint(o,'titanium')
    for frac,color in ((.20,'marking_yellow'),(-.22,'hazard_red')):
        paint(b.cylinder(0,0,L*frac,L*frac+L*.018,R*1.015,32,'band','x'),color)
    paint(b.cylinder(0,0,-L*.501,-L*.498,R*.62,32,'nozzle','x'),'rubber')


def studio(scene):
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'
    scene.cycles.samples=40
    scene.cycles.use_denoising=True
    scene.cycles.max_bounces=4
    scene.render.film_transparent=True
    scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA'
    scene.render.image_settings.compression=90
    scene.render.use_freestyle=False
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    world=scene.world or bpy.data.worlds.new('studio_world')
    scene.world=world
    world.use_nodes=True
    bg=world.node_tree.nodes['Background']
    bg.inputs[0].default_value=(.24,.34,.46,1)
    bg.inputs[1].default_value=.45


def light(scene,direction,power,color):
    o=b.add_sun(scene,direction,power)
    o.data.color=color
    o.data.angle=.15


def prepare_normals():
    bpy.ops.object.select_all(action='DESELECT')
    for o in b._objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active=b._objects[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')


def output_asset(spec,scene,is_weapon=False):
    sid=spec['id']
    b.clear_scene()
    if is_weapon:weapon_model(spec)
    else:
        if sid in ('usn_ddg_burke_iii','usn_ddg_arleigh_burke_iia'):burke(spec)
        elif sid in ('usn_fighter_f35c','rn_fighter_f35b'):lightning(spec)
        else:b.BUILDERS.get(sid,b.generic_builder)(spec)
        finish_materials(spec)
    prepare_normals()
    bpy.context.view_layer.update()
    lo,hi=b.scene_bounds()
    L=(hi-lo).length
    light(scene,(-.3,-.7,1.5),3.1,(1,.88,.73))
    light(scene,(.3,.8,1.0),2.3,(.58,.78,1))
    light(scene,(1,.2,.5),.9,(.84,.95,1))
    direction=(.63,-1,.66) if not is_weapon else (.18,-1,.52)
    if spec.get('domain')=='air':direction=(.62,-1,.88)
    cam_obj,cam=b.place_camera(scene,(lo+hi)*.5,1200,640,direction,L*8)
    b.fit_camera(cam_obj,cam,b.scene_vertices(),1200/640,1.16)
    out=WEAPONS if is_weapon else ART
    out.mkdir(parents=True,exist_ok=True)
    b.render(scene,str(out/(sid+'_thumb.png')),240,128)
    if THUMBS_ONLY:
        return None
    b.render(scene,str(out/(sid+'_beauty.png')),1200,640)
    if not is_weapon:
        # Colour plan silhouettes retain the original scale contract used by the map.
        length,span=hi.x-lo.x,hi.y-lo.y
        w,h=(768,max(8,round(768*span/length))) if length>=span else (max(8,round(768*length/span)),768)
        cam_obj,cam=b.place_camera(scene,(lo+hi)*.5,w,h,(0,0,1),L*8)
        cam_obj.rotation_euler=(0,0,0)
        cam.ortho_scale=max(length,span)*1.10
        b.render(scene,str(out/(sid+'_plan.png')),w,h)
    # Runtime model: apply bevels then combine into one mesh with a small material palette.
    bpy.ops.object.select_all(action='DESELECT')
    for o in b._objects:
        bpy.context.view_layer.objects.active=o
        for modifier in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=modifier.name)
        o.select_set(True)
    bpy.context.view_layer.objects.active=b._objects[0]
    bpy.ops.object.join()
    o=bpy.context.object
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    lo,hi=bounds(o)
    center=(lo+hi)*.5
    scale=10/max(hi-lo)
    for v in o.data.vertices:v.co=(v.co-center)*scale
    o.name=sid
    MODELS.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(MODELS/(sid+'.glb')),export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_animations=False,export_yup=True,export_extras=False)
    tris=sum(len(p.vertices)-2 for p in o.data.polygons)
    print('ASSET',sid,'triangles',tris,flush=True)
    return {'id':sid,'kind':'weapon' if is_weapon else 'platform','triangles':tris}


def main():
    global THUMBS_ONLY
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    THUMBS_ONLY='--thumbs' in args
    wanted={arg for arg in args if not arg.startswith('--')}
    palette()
    scene=bpy.context.scene
    studio(scene)
    manifest=[]
    all_specs=[(s,False) for s in b.read_specs().values()]+[(s,True) for s in weapon_specs().values()]
    for spec,is_weapon in all_specs:
        if wanted and spec['id'] not in wanted:continue
        item=output_asset(spec,scene,is_weapon)
        if item:manifest.append(item)
    if THUMBS_ONLY:
        print('THUMBNAILS COMPLETE',flush=True)
        return
    rendered_count=len(manifest)
    if wanted and (MODELS/'manifest.json').exists():
        existing=json.loads((MODELS/'manifest.json').read_text())
        changed={item['id'] for item in manifest}
        manifest=[item for item in existing if item['id'] not in changed]+manifest
    (MODELS/'manifest.json').write_text(json.dumps(sorted(manifest,key=lambda item:item['id']),indent=2)+'\n')
    print('PRESENTATION COMPLETE',rendered_count,'rendered;',len(manifest),'catalogued',flush=True)


if __name__=='__main__':main()
