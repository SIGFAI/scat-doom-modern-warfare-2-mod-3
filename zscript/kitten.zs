// Shadow Kitten: the enemy cat operator in a skull balaclava. Fires 3-round bursts of visible tracers.
class ShadowKitten : Actor replaces ZombieMan
{
	Default
	{
		Health 50;
		Radius 18;
		Height 56;
		Mass 100;
		Speed 9;
		PainChance 200;
		Monster;
		+FLOORCLIP
		SeeSound "kitten/sight";
		PainSound "kitten/pain";
		DeathSound "kitten/death";
		ActiveSound "kitten/sight";
		AttackSound "kitten/rifle";
		Obituary "%o was out-flanked by a Shadow Kitten.";
		Tag "Shadow Kitten";
		DropItem "Clip";
	}

	bool inBox; Actor lure;   // squeezed inside the box; the care package it runs to

	int firedAt;       // last shot, for the minimap (firing shows you on radar)
	double ropeTop;    // fast-roping down from the ceiling (KittenSquad)
	bool roping;

	override void Tick()
	{
		Super.Tick();
		if (bDestroyed) return;
		if (health > 0 && !lure && !inBox && level.maptime % 35 == 0 && (!target || target.player)) HuntDemons();
		if (!roping) return;
		if (pos.z <= floorz + 0.5)
		{
			roping = false;
			A_StartSound("box/thud", CHAN_BODY, CHANF_OVERLAP, 0.5, 1.2);
			return;
		}
		vel.z = max(vel.z, -5);
		// The rope: a dark line from the paws up to the ceiling.
		for (double z = height; z < ropeTop - pos.z; z += 6)
			A_SpawnParticle("2A2018", 0, 2, 2.5, 0, 0, 0, z, 0, 0, 0, 0, 0, 0, 1.0, 0);
	}

	// Task Furce or not, a cat hates a demon: a Doom monster in view becomes the target, and it fights back.
	void HuntDemons()
	{
		let it = BlockThingsIterator.Create(self, 700);
		while (it.Next())
		{
			let d = it.thing;
			if (!d || d == self || !d.bIsMonster || d.health <= 0 || d is "ShadowKitten" || d.bFriendly) continue;
			if (!CheckSight(d)) continue;
			target = d;
			if (!d.target || d.target.player) d.target = self;
			return;
		}
	}

	// No cat can resist a box: drop the fight and run to it.
	void StartLure(Actor box)
	{
		lure = box;
		A_StartSound("kitten/sight", CHAN_VOICE);
		SetStateLabel("Lured");
	}

	void LureStep()
	{
		if (!lure || lure.bDestroyed)
		{
			lure = null;
			SetState(SeeState);
			return;
		}
		A_Face(lure, 15);
		double reach = radius + lure.radius + 12;
		if (Distance2D(lure) <= reach)
		{
			let box = CarePackage(lure);
			if (box) box.CatEnter(self);
			return;
		}
		// Run, a bit faster than usual; slide along walls by trying to the sides.
		double sp = speed * 1.5;
		if (!TryMove(Vec2Angle(sp, angle), 0) && !TryMove(Vec2Angle(sp, angle + 50), 0)) TryMove(Vec2Angle(sp, angle - 50), 0);
		if (level.maptime % 12 == 0)
			A_SpawnParticle("FF60A0", SPF_FULLBRIGHT, 20, 6, 0, 0, 0, height + 10, 0, 0, 0.8, 0, 0, 0, 1.0, -0.05);
	}

	void KittenShot()
	{
		firedAt = level.maptime;
		A_StartSound(AttackSound, CHAN_WEAPON, CHANF_OVERLAP);
		A_SpawnProjectile("CatTracer", 34, 6, frandom(-4, 4), CMF_OFFSETPITCH, frandom(-1.5, 1.5));
		A_AttachLight('muzzle', DynamicLight.PointLight, "FFC060", 64, 0);
	}

	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		int dealt = Super.DamageMobj(inflictor, source, damage, mod, flags, angle);
		if (dealt > 0) CatFx.Fur(self, 6, height * 0.6);
		return dealt;
	}

	States
	{
	Spawn:
		SKIT A 10 A_Look;
		Loop;
	See:
		SKIT AABB 4 A_Chase;
		Loop;
	Missile:
		SKIT A 8 A_FaceTarget;
		SKIT E 2 Bright KittenShot;
		SKIT A 2 { A_FaceTarget(); A_RemoveLight('muzzle'); }
		SKIT E 2 Bright KittenShot;
		SKIT A 2 { A_FaceTarget(); A_RemoveLight('muzzle'); }
		SKIT E 2 Bright KittenShot;
		SKIT A 10 A_RemoveLight('muzzle');
		Goto See;
	Lured:
		SKIT AABB 3 LureStep;
		Loop;
	InBox:
		TNT1 A -1;
		Stop;
	Pain:
		SKIT F 0 { if (lure) return ResolveState("PainLured"); return ResolveState(null); }
		SKIT F 4;
		SKIT F 6 A_Pain;
		Goto See;
	PainLured:
		SKIT F 6 A_Pain;
		Goto Lured;
	Death:
	XDeath:
		SKIT G 4 { CatFx.Fur(self, 30, 30); A_Scream(); }
		SKIT G 6 A_NoBlocking;
		SKIT H -1;
		Stop;
	Raise:
		SKIT H 6;
		SKIT G 6;
		Goto See;
	}
}

// Squad insertion, Modern Warfare style: Shadow Kittens fast-rope down from the ceiling a few rooms' length ahead
// of the player, in view, so they are seen whole before the fight (summon KittenSquad / KittenSquad3).
class KittenSquad : Actor
{
	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
	}

	virtual int SquadSize() { return 2; }

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		Insert("ShadowKitten", SquadSize(), true);
		Destroy();
	}

	// Puts n monsters on the floor 300-640 units ahead of the player, in his view; kittens fast-rope down.
	static int Insert(Class<Actor> cls, int n, bool rope, double near = 300, double far = 640)
	{
		let mo = players[consoleplayer].mo;
		int made = 0;
		for (int i = 0; mo && i < 160 && made < n; i++)
		{
			// Ahead and in view first; then wider, closer, and at last anywhere around (a big body needs room).
			double spread = i < 50 ? 40 : (i < 100 ? 110 : 180);
			double reach = i < 100 ? 1. : 0.5;
			Vector2 xy = mo.Vec2Angle(frandom(near * reach, far * reach), mo.angle + frandom(-spread, spread));
			let sec = level.PointInSector(xy);
			double fz = sec.floorplane.ZatPoint(xy), cz = sec.ceilingplane.ZatPoint(xy);
			if (abs(fz - mo.pos.z) > 96) continue;
			let m = Actor.Spawn(cls, (xy, fz), ALLOW_REPLACE);
			if (!m) continue;
			if (!m.TestMobjLocation() || (i < 130 && !m.CheckSight(mo, SF_IGNOREVISIBILITY)))
			{
				m.ClearCounters();
				m.Destroy();
				continue;
			}
			let k = ShadowKitten(m);
			if (k && rope)
			{
				k.SetOrigin((xy, max(fz, min(cz - k.height - 2, fz + 150))), false);
				k.ropeTop = cz;
				k.roping = k.pos.z > fz + 8;
			}
			else Actor.Spawn("TeleportFog", m.pos, ALLOW_REPLACE);
			m.target = mo;
			m.SetState(m.SeeState);
			made++;
		}
		return made;
	}
}

class KittenSquad3 : KittenSquad
{
	override int SquadSize() { return 3; }
}
