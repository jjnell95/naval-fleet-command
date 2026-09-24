"""Original recognition geometry for the 1990 catalogue.

Class-defining external shapes, not engineering models: exposed launchers, conventional
masts and gun mounts, propeller submarines, turboprops and variable-sweep aircraft.
Dimensions follow the game's public identity records. Small fittings are illustrative.
"""
import math
from types import SimpleNamespace


def register(api):
    b = SimpleNamespace(**api)

    def launcher(x, y, z, twin=False):
        b.cylinder(x,y,z,z+1.5,1.0,12,"launcher_pedestal")
        b.cbox(x,y,z+2.0,4.6,.65,1.0,"missile_rail")
        for side in (-1,1) if twin else (0,):
            b.cylinder(y+side*.8,z+2.6,x-1.8,x+2.6,.18,8,"ready_missile","x")

    def canisters(x, y, z, count, length=8.0, radius=.65):
        for i in range(count):
            # Local origin keeps the whole pack raised above the deck when inclined.
            yy=y+((i%2)-.5)*radius*2.25 if count==4 else y+(i-(count-1)/2)*radius*2.25
            zz=(i//2)*radius*2.25 if count==4 else 0
            o=b.cylinder(yy,zz,-length/2,length/2,radius,12,"tube","x")
            o.rotation_euler.y=-.20
            o.location=(x,0,z)

    def escort(L, kind):
        perry=kind=="perry"
        B=L*(.099 if perry else .098)
        fa,ff=(3.2,5.5) if perry else (4.1,7.2)
        b.hull(L,B,5.2 if perry else 6.0,fa,ff,stations=36)
        x=lambda t:L*(t-.5)
        d=lambda t:b.deck_z(fa,ff,t)
        b.box(x(.29),x(.66),-B*.40,B*.40,d(.45),d(.45)+5.4,"deckhouse")
        b.box(x(.53),x(.65),-B*.36,B*.36,d(.45)+5.4,d(.45)+9.0,"bridge")
        b.hangar(x(.16),x(.31),B,d(.23),5.4)
        b.lattice_mast(x(.55),0,d(.45)+9.0,d(.45)+23.5,3.2,1.0)
        b.cbox(x(.55),0,d(.45)+24.4,1.0,6.5,1.5,"search_array")
        b.mast(x(.33),0,d(.35)+5.4,d(.35)+17.0,.23,5.0)
        if perry:
            b.funnel(x(.39),0,d(.45)+5.4,5.0,3.0,4.8,-.3)
            launcher(x(.80),0,d(.80))  # single-arm Mk 13, no VLS
            b.gun(x(.45),0,d(.45)+5.5,big=False)
            b.ciws(x(.19),0,d(.23)+5.4)
        else:
            for t in (.44,.33):b.funnel(x(t),0,d(.45)+5.4,5.4,3.6,5.4,-.4)
            b.gun(x(.81),0,d(.81))
            # Aft gun has its barrel trained astern in this recognition pose.
            b.cbox(x(.07),0,d(.07)+1.6,6,4,3,"turret")
            b.cylinder(0,d(.07)+2.4,x(.07)-9.5,x(.07)-3,.25,8,"barrel","x")
            b.vls(x(.68),x(.76),0,d(.71),B*.56,4)
            for s in (-1,1):canisters(x(.36),s*B*.31,d(.45)+7,4,4.7,.27)
            b.ciws(x(.64),-B*.32,d(.45)+5.4)
            b.ciws(x(.20),B*.32,d(.23)+5.4)
        for s in (-1,1):b.boat(x(.42),s*B*.43,d(.4))

    def sovremenny(L):
        B=L*.112; fa,ff=4.3,7.2
        x=lambda t:L*(t-.5); d=lambda t:b.deck_z(fa,ff,t)
        b.hull(L,B,6.1,fa,ff,stations=36)
        b.box(x(.28),x(.67),-B*.36,B*.36,d(.45),d(.45)+5.8,"deckhouse")
        b.box(x(.53),x(.66),-B*.32,B*.32,d(.45)+5.8,d(.45)+11,"bridge")
        b.lattice_mast(x(.54),0,d(.45)+11,d(.45)+26,4,1.3)
        b.cbox(x(.54),0,d(.45)+27,1.3,6.6,2.0,"top_plate")
        b.lattice_mast(x(.30),0,d(.35)+6,d(.35)+18,3,1)
        b.funnel(x(.43),0,d(.45)+5.8,7.0,5,6)
        b.hangar(x(.23),x(.32),B*.67,d(.26)+.2,4.7)
        b.gun(x(.83),0,d(.83),twin=True)
        b.cbox(x(.10),0,d(.1)+1.6,6,4,3,"turret")
        for yy in (-.65,.65):b.cylinder(yy,d(.1)+2.4,x(.1)-9.5,x(.1)-3,.25,8,"barrel","x")
        launcher(x(.73),0,d(.73),False)
        launcher(x(.19),0,d(.19)+1,False)
        for s in (-1,1):
            canisters(x(.69),s*B*.39,d(.67)+2.4,4,9,.62)
            b.ciws(x(.47),s*B*.33,d(.45)+5.8)

    def nanuchka(L):
        B=L*.187; fa,ff=2.3,3.7
        x=lambda t:L*(t-.5); d=lambda t:b.deck_z(fa,ff,t)
        b.hull(L,B,3.0,fa,ff,stations=28)
        b.box(x(.30),x(.65),-B*.30,B*.30,d(.45),d(.45)+3.8,"deckhouse")
        b.box(x(.48),x(.63),-B*.27,B*.27,d(.45)+3.8,d(.45)+6.4,"bridge")
        b.lattice_mast(x(.45),0,d(.45)+6.4,d(.45)+15,2.4,.8)
        b.cbox(x(.45),0,d(.45)+15.6,1.0,4.8,1.3,"search_array")
        b.funnel(x(.33),0,d(.45)+3.8,3.0,2.2,2.8)
        for s in (-1,1):canisters(x(.49),s*B*.35,d(.45)+1.2,3,8.5,.57)
        launcher(x(.78),0,d(.78))
        b.gun(x(.13),0,d(.13),big=False)
        b.ciws(x(.27),0,d(.27)+3.8)

    def submarine(L, soviet=False):
        R=L*(.050 if soviet else .046)
        # Blunt sonar bow to +X; fine stern with an exposed screw at -X.
        b.fuselage(L,R,nose=.105,tail=.31,taper=.12).name="pressure_hull"
        le=L*(.12 if soviet else .20)
        b.vplate([(le-L*.14,R*.86),(le,R*.86),(le-L*.01,R*2.22),(le-L*.12,R*2.22)],-R*.35,R*.35,"sail")
        if not soviet:
            b.plate([(le-L*.04,-R*1.7),(le-L*.09,-R*1.7),(le-L*.09,R*1.7),(le-L*.04,R*1.7)],R*1.55,R*1.7,"sail_planes")
        else:
            b.plate([(L*.32,-R*1.45),(L*.25,-R*1.45),(L*.25,R*1.45),(L*.32,R*1.45)],-.15,.15,"bow_planes")
        for a in (0,math.pi/2,math.pi,math.pi*1.5):
            o=b.plate([(-L*.33,0),(-L*.43,0),(-L*.45,R*1.85),(-L*.38,R*1.75)],-.12,.12,"stern_fin")
            o.rotation_euler.x=a
        if soviet:
            # Characteristic Victor III towed-array pod on the upper rudder.
            b.cylinder(0,R*1.70,-L*.48,-L*.31,R*.31,16,"towed_array_pod","x")
        for i in range(7):
            o=b.plate([(-L*.51,0),(-L*.49,R*.8),(-L*.47,R*.95),(-L*.46,0)],-.07,.07,"propeller")
            o.rotation_euler.x=i*math.tau/7
        for t in (.04,.07):b.mast(L*t,0,R*2.2,R*2.85,.08)

    def tomcat(L):
        b.fuselage(L,L*.045,nose=.33,tail=.30,taper=.28)
        for s in (-1,1):
            # Broad fixed glove plus moderately swept variable wing, twin-spaced engines.
            b.plate([(L*.23,s*.65),(-L*.30,s*.65),(-L*.20,s*L*.17),(L*.08,s*L*.16)],-.15,.18,"glove")
            b.plate([(L*.04,s*L*.13),(-L*.16,s*L*.15),(-L*.36,s*L*.46),(-L*.28,s*L*.46)],-.12,.12,"wing")
            b.plate([(-L*.30,s*.6),(-L*.48,s*.6),(-L*.48,s*L*.22),(-L*.40,s*L*.24)],-.12,.12,"stab")
            b.engine_pod(-L*.49,L*.04,s*L*.085,-L*.026,L*.035)
            b.cbox(L*.04,s*L*.085,-L*.02,L*.16,L*.068,L*.075,"intake")
            b.fin(-L*.25,L*.18,L*.07,L*.17,L*.10,y=s*L*.105,cant=-s*.08,thickness=.14)
        b.cbox(L*.23,0,L*.045,L*.22,L*.065,L*.065,"canopy")

    def patrol(L, orion=False):
        if orion:
            bodyL=L*.91
            b.fuselage(bodyL,L*.044,nose=.15,tail=.30,taper=.2)
            span=L*.86
            b.wing(L,span,L*.16,L*.065,L*.11,L*.12,0,thickness=.20)
            for s in (-1,1):
                for yy in (L*.15,L*.30):
                    xx=L*.10-yy*.18
                    b.engine_pod(xx-L*.10,xx+L*.04,s*yy,0,L*.019)
                    b.cylinder(s*yy,0,xx+L*.04,xx+L*.045,L*.047,16,"prop_disc","x")
            b.cylinder(0,0,-L*.53,-L*.34,L*.008,12,"mad_boom","x")
        else:
            b.fuselage(L,L*.078,nose=.20,tail=.30,taper=.22)
            b.wing(L,L*1.15,L*.24,L*.09,L*.07,L*.09,L*.06,thickness=.22)
            for s in (-1,1):b.engine_pod(-L*.14,L*.06,s*L*.24,-L*.075,L*.045)
        b.wing(L,L*.36,L*.12,L*.055,L*.045,-L*.30,L*.025,thickness=.13)
        b.fin(-L*.27,L*.18,L*.06,L*(.19 if orion else .25),L*.10,thickness=.16)
        b.cbox(L*.29,0,L*.05,L*.13,L*.095,L*.052,"canopy")

    def seaking(L):
        prof=[(L*.38,0),(L*.34,L*.06),(L*.23,L*.082),(-L*.03,L*.085),(-L*.15,L*.055),(-L*.45,L*.018),(-L*.48,0)]
        b.revolve(prof,20,"cabin")
        for s in (-1,1):b.engine_pod(-L*.12,L*.20,s*L*.037,L*.075,L*.035)
        for s in (-1,1):
            o=b.fuselage(L*.24,L*.035,nose=.18,tail=.2,segs=14,taper=.3)
            o.location=(-L*.02,s*L*.11,-L*.04);o.name="sponson"
        b.vplate([(-L*.42,0),(-L*.48,0),(-L*.45,L*.17),(-L*.38,L*.14)],-.1,.1,"fin")
        b.cylinder(L*.07,0,L*.12,L*.16,L*.014,12,"rotor_mast")
        for i in range(5):
            a=i*math.tau/5+.25
            pts=[(L*.07+math.cos(a)*r,math.sin(a)*r) for r in (L*.025,L*.44)]
            pts.extend([(pts[1][0]-math.sin(a)*L*.015,pts[1][1]+math.cos(a)*L*.015),(pts[0][0]-math.sin(a)*L*.015,pts[0][1]+math.cos(a)*L*.015)])
            b.plate(pts,L*.157,L*.162,"blade")
            rr=L*.09
            b.vplate([(-L*.43,L*.13),(-L*.43+math.cos(a)*rr,L*.13+math.sin(a)*rr),(-L*.43+math.cos(a)*rr-.12,L*.13+math.sin(a)*rr+.12)],L*.027,L*.035,"tail_blade")
        b.cbox(L*.28,0,L*.03,L*.13,L*.105,L*.07,"canopy")

    return {
        "cw90_perry":lambda s:escort(s["length_m"],"perry"),
        "cw90_spruance":lambda s:escort(s["length_m"],"spruance"),
        "cw90_sovremenny":lambda s:sovremenny(s["length_m"]),
        "cw90_nanuchka":lambda s:nanuchka(s["length_m"]),
        "cw90_los_angeles":lambda s:submarine(s["length_m"]),
        "cw90_victor3":lambda s:submarine(s["length_m"],True),
        "cw90_f14a":lambda s:tomcat(s["length_m"]),
        "cw90_p3c":lambda s:patrol(s["length_m"],True),
        "cw90_s3a":lambda s:patrol(s["length_m"]),
        "cw90_sh3h":lambda s:seaking(s["length_m"]),
        "cw90_ticonderoga":lambda s:b.build_ticonderoga(s["length_m"]),
        "cw90_nimitz":lambda s:b.build_carrier(s["length_m"]),
        "cw90_udaloy":lambda s:b.build_udaloy(s["length_m"]),
        "cw90_slava":lambda s:b.build_slava(s["length_m"]),
        "cw90_sh60b":lambda s:b.build_helicopter(s["length_m"]),
        "cw90_ka27":lambda s:b.build_merlin(s["length_m"],True),
        "cw90_e2c":lambda s:b.build_patrol(s["length_m"],"hawkeye"),
        "cw90_tu22m3":lambda s:b.build_bomber(s["length_m"]),
        "cw90_airfield":lambda s:b.build_air_station(),
        "cw90_merchant":lambda s:b.build_merchant(s["length_m"]),
    }
