# Monte Carlo behind docs/research/ios-techniques.md section 4.
# Model: AEA alerts a device when the epicenter is within R(M) of it (radius table in docs/findings.md).
# "miss" = the user phone would alert (epicenter within R of the user) but no chosen receptor would.
# Epicenters uniform over the disc. Flat plane, km. Run: python3 receptor-edge-sim.py
import numpy as np
rng=np.random.default_rng(1)
R={'M4.5':31,'M5.0':78,'M5.5':197,'M6.0':346}
N=400000
def miss(Rm, recs):
    # epicenters uniform over disc radius Rm around user (user's own phone would alert)
    r=Rm*np.sqrt(rng.random(N)); t=2*np.pi*rng.random(N)
    E=np.stack([r*np.cos(t),r*np.sin(t)],1)
    hit=np.zeros(N,bool)
    for p in recs: hit|=np.linalg.norm(E-np.array(p),axis=1)<=Rm
    return 1-hit.mean()
def fp(Rm, recs):
    # epicenters uniform in annulus Rm..2Rm; receptor alerts but user would not
    r=Rm*np.sqrt(1+3*rng.random(N)); t=2*np.pi*rng.random(N)
    E=np.stack([r*np.cos(t),r*np.sin(t)],1)
    hit=np.zeros(N,bool)
    for p in recs: hit|=np.linalg.norm(E-np.array(p),axis=1)<=Rm
    return hit.mean()  # share of annulus quakes (Rm..2Rm) that still alert us
print("d_km  " + "  ".join(f"{m:>6}" for m in R)+"   (miss share, 1 receptor)")
for d in [5,10,20,31,50,78]:
    print(f"{d:4d}  "+"  ".join(f"{100*miss(R[m],[(d,0)]):5.1f}%" for m in R))
print("\n2 receptors, both at d, opposite sides / 90deg / same side")
for d in [20,31,50,78]:
    for name,recs in [("opp",[(d,0),(-d,0)]),("90",[(d,0),(0,d)]),("same",[(d,0),(d*.98,d*.2)])]:
        print(f"{d:3d} {name:4s} "+"  ".join(f"{100*miss(R[m],recs):5.1f}%" for m in R))
print("\n3 receptors at 120deg, d=31,50,78")
for d in [31,50,78]:
    recs=[(d*np.cos(a),d*np.sin(a)) for a in (0,2*np.pi/3,4*np.pi/3)]
    print(f"{d:3d} 120deg "+"  ".join(f"{100*miss(R[m],recs):5.1f}%" for m in R))
print("\nnearest at d1 + 2nd at d2 (same side vs opp), d1=20")
for d2 in [40,60,78]:
    for name,sgn in [("opp",-1),("same",1)]:
        print(f"d2={d2} {name:4s} "+"  ".join(f"{100*miss(R[m],[(20,0),(sgn*d2,0)]):5.1f}%" for m in R))
