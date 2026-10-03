// Killstreaks, the SuperIntelligent Cat way: UAV (3 kills), Care Package (5), Predator Missile (7).

// UAV: a cat on a surveillance drone hovers ahead of the player, sweeping a green scan beam;
// while it flies, every enemy shows on the minimap.
class UAVDrone : Actor
{
	const LIFE = 35 * 30;
	int born;
	double phase;

	Default
	{
		+NOINTERACTION
		+NOGRAVITY
		+FORCEXYBILLBOARD
		Scale 1.25;
		Radius 16;
		Height 20;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		born = level.maptime;
		phase = frandom(0, 360);
	}

	override void Tick()
	{
		Super.Tick();
		let mo = target;
		if (!mo || level.maptime - born > LIFE)
		{
			Spawn("TeleportFog", pos, ALLOW_REPLACE);
			Destroy();
			return;
		}
		// Hover ahead of the player, weaving left and right, high enough to read as "in the sky".
		double t = (level.maptime - born) * 2.0 + phase;
		Vector2 ahead = mo.Vec2Angle(150, mo.angle + sin(t) * 30);
		double ceil = level.PointInSector(ahead).ceilingplane.ZatPoint(ahead);
		double z = min(mo.pos.z + 88 + sin(t * 2.3) * 6, ceil - 26);
		SetOrigin((ahead, z), true);
		angle = mo.angle + 180;
		// Scan beam: a thin green cone of particles down to the floor.
		if (level.maptime % 2 == 0)
		{
			double fz = level.PointInSector(pos.xy).floorplane.ZatPoint(pos.xy);
			double sweep = sin(t * 3) * 40;
			for (int i = 1; i < 7; i++)
			{
				double f = i / 7.;
				Vector2 o = Actor.AngleToVector(mo.angle + 90, sweep * f);
				A_SpawnParticle("40FF70", SPF_FULLBRIGHT, 4, 2.5, 0, o.x, o.y, -(pos.z - fz) * f, 0, 0, 0, 0, 0, 0, 0.7, -0.15);
			}
		}
		if ((level.maptime - born) % 70 == 0) A_StartSound("uav/ping", CHAN_BODY, CHANF_OVERLAP, 0.6, ATTN_NONE);
	}

	States
	{
	Spawn:
		UAVD A -1 Bright;
		Stop;
	}
}

// Care package: a cardboard crate drops from the sky. No cat can resist a box: every Shadow Kitten nearby
// stops fighting and squeezes in. Then the SuperIntelligent Cat reveals it was a trap.
class CarePackage : Actor
{
	Array<ShadowKitten> inside;
	int landedAt, firstCatAt;
	bool blown;

	Default
	{
		Radius 36;
		Height 58;
		Scale 1.15;
		Health 300;
		Mass 1000;
		Gravity 0.6;
		+SOLID
		+SHOOTABLE
		+NOBLOOD
		+DONTTHRUST
		+NOTAUTOAIMED
		Tag "Care Package";
	}

	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		// Only the player's side can set it off early (shoot the box!).
		if (!MW2Handler.IsPlayerSide(source)) return 0;
		CatFx.Sparks(self, 4, "C09050");
		return Super.DamageMobj(inflictor, source, damage, mod, flags, angle);
	}

	override void Tick()
	{
		Super.Tick();
		if (blown || bDestroyed) return;
		bool onFloor = pos.z <= floorz + 1;
		if (onFloor && !landedAt)
		{
			landedAt = level.maptime;
			A_StartSound("box/thud", CHAN_BODY, 0, 1.0, 0.6);
			A_Quake(2, 8, 0, 300);
			for (int i = 0; i < 20; i++)
				A_SpawnParticle("9A8A70", 0, 30, frandom(5, 9), 0, frandom(-20, 20), frandom(-20, 20), 2,
					frandom(-3, 3), frandom(-3, 3), frandom(0.5, 2), 0, 0, 0, 0.8, -0.025);
			MW2Handler.Get().Say("They cannot resist a box. No cat can.", "sic/box", 145);
		}
		if (!landedAt)
		{
			// Falling: a red smoke flare marks where it will land.
			return;
		}
		int since = level.maptime - landedAt;
		// Red marker smoke, like a real supply drop.
		if (level.maptime % 3 == 0)
			A_SpawnParticle(random(0, 1) ? "E02020" : "B01818", 0, 70, frandom(8, 14), 0, frandom(-6, 6), frandom(-6, 6), height,
				frandom(-0.4, 0.4), frandom(-0.4, 0.4), frandom(1.0, 1.8), 0, 0, 0, 0.55, -0.008, 0.25);
		// Call every kitten in range.
		if (since % 5 == 0)
		{
			let it = ThinkerIterator.Create("ShadowKitten");
			ShadowKitten k;
			while (k = ShadowKitten(it.Next()))
			{
				if (k.health > 0 && !k.lure && !k.inBox && Distance2D(k) < 1600) k.StartLure(self);
			}
		}
		if (inside.Size() && !firstCatAt) firstCatAt = level.maptime;
		bool full = inside.Size() >= 3;
		if ((firstCatAt && level.maptime - firstCatAt > 35 * 3) || (full && level.maptime - firstCatAt > 50) || since > 35 * 9)
			Detonate();
	}

	void CatEnter(ShadowKitten k)
	{
		if (blown || inside.Find(k) != inside.Size()) return;
		inside.Push(k);
		k.inBox = true;
		k.bIsMonster = false;   // out of the fight while it sits
		k.bInvisible = true;
		k.bShootable = false;
		k.bSolid = false;
		k.bNoGravity = true;
		k.SetOrigin(pos, false);
		k.vel = (0, 0, 0);
		k.SetStateLabel("InBox");
		A_StartSound("box/purr", CHAN_VOICE, CHANF_OVERLAP, 1.0, 0.7);
		SetStateLabel("Full");
		MW2Handler.Get().Popup(String.Format("IF IT FITS, I SITS  x%d", inside.Size()), Color(255, 255, 170, 60));
	}

	override void Die(Actor source, Actor inflictor, int dmgflags, Name MeansOfDeath)
	{
		if (!blown) Detonate();
	}

	void Detonate()
	{
		if (blown) return;
		blown = true;
		let boss = MW2Handler.Get().PlayerActor();
		MW2Handler.Get().Say("If it fits, it sits. And it was a bomb.", "sic/trap", 170);
		let fx = Spawn("CatExplosion", pos + (0, 0, 16), ALLOW_REPLACE);
		if (fx) fx.target = boss;
		// The cats inside fly out in every direction.
		for (int i = 0; i < inside.Size(); i++)
		{
			let k = inside[i];
			if (!k || k.health <= 0) continue;
			k.inBox = false;
			k.bIsMonster = true;
			k.bInvisible = false;
			k.bShootable = true;
			k.bNoGravity = false;
			double a = i * 360. / inside.Size() + frandom(-20, 20);
			k.SetOrigin(pos + (Actor.AngleToVector(a, 20), 28), false);
			k.vel = (Actor.AngleToVector(a, frandom(7, 10)), frandom(9, 13));
			k.DamageMobj(fx, boss, 1000, 'Explosive', DMG_FORCED);
		}
		inside.Clear();
		target = boss;
		A_Explode(120, 160, 0, false, 0, 0, 0, "", 'Explosive');
		Destroy();
	}

	States
	{
	Spawn:
		CBOX A -1;
		Stop;
	Full:
		CBOX B -1;
		Stop;
	}
}

// The big boom: Doom's own explosion frames blown up, plus fire, smoke, debris, a shockwave ring and a quake.
class CatExplosion : Actor
{
	Default
	{
		+NOINTERACTION
		+NOGRAVITY
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Scale 3.2;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		A_StartSound("pred/boom", CHAN_BODY, CHANF_OVERLAP, 1.0, 0.35);
		A_AttachLight('blast', DynamicLight.PointLight, "FFB040", 420, 0);
		A_Quake(6, 22, 0, 900, "");
		for (int i = 0; i < 70; i++)
		{
			double a = frandom(0, 360), s = frandom(3, 11);
			A_SpawnParticle(random(0, 2) ? "FFB030" : "FFF0A0", SPF_FULLBRIGHT, random(18, 34), frandom(6, 13), 0,
				0, 0, frandom(0, 20), cos(a) * s, sin(a) * s, frandom(1, 9), 0, 0, -0.3, 1.0, -0.035, -0.15);
		}
		for (int i = 0; i < 36; i++)
		{
			double a = frandom(0, 360), s = frandom(1, 4);
			A_SpawnParticle(random(0, 1) ? "404040" : "6A6058", 0, random(45, 70), frandom(12, 20), 0,
				frandom(-20, 20), frandom(-20, 20), frandom(0, 40), cos(a) * s, sin(a) * s, frandom(0.6, 2.2), 0, 0, 0, 0.7, -0.011, 0.22);
		}
		// Shockwave ring along the floor.
		for (int i = 0; i < 48; i++)
		{
			double a = i * 7.5;
			A_SpawnParticle("FFE0A0", SPF_FULLBRIGHT, 14, 7, 0, 0, 0, 4, cos(a) * 14, sin(a) * 14, 0, 0, 0, 0, 0.9, -0.065);
		}
		for (int i = 0; i < 6; i++)
		{
			let d = Spawn("CatDebris", pos + (0, 0, 10), ALLOW_REPLACE);
			if (d) d.vel = (frandom(-9, 9), frandom(-9, 9), frandom(6, 14));
		}
	}

	States
	{
	Spawn:
		MISL B 5 Bright A_SetScale(3.6);
		MISL C 6 Bright { A_SetScale(4.2); A_AttachLight('blast', DynamicLight.PointLight, "FF8020", 300, 0); }
		MISL D 7 Bright { A_SetScale(4.6); A_AttachLight('blast', DynamicLight.PointLight, "A04010", 160, 0); }
		Stop;
	}
}

// Burning chunks thrown by an explosion, trailing smoke until they land.
class CatDebris : Actor
{
	Default
	{
		Radius 3;
		Height 3;
		Gravity 0.7;
		+NOBLOCKMAP
		+DROPOFF
		+MISSILE
		+NOTELEPORT
		+BOUNCEONFLOORS
		BounceFactor 0.3;
		BounceCount 2;
	}

	override void Tick()
	{
		Super.Tick();
		if (!bDestroyed && level.maptime % 2 == 0)
		{
			A_SpawnParticle("FF9020", SPF_FULLBRIGHT, 10, 5, 0, 0, 0, 0, 0, 0, 0.3, 0, 0, 0, 1.0, -0.1);
			A_SpawnParticle("505050", 0, 30, 7, 0, 0, 0, 0, 0, 0, 0.6, 0, 0, 0, 0.6, -0.02, 0.2);
		}
	}

	States
	{
	Spawn:
		TNT1 A 70;
		Stop;
	Death:
		TNT1 A 1;
		Stop;
	}
}

// Predator missile: Mr. Whiskers rides a guided missile from over the player's shoulder, arcs up under the
// ceiling and dives into the biggest group of enemies. A missile-cam inset shows his view. Flown by hand along a
// curve (not a plain projectile) so it lasts long enough to be seen, whatever the room.
class PredatorMissile : Actor
{
	Vector3 from, ctrl, dest;
	int t, dur;
	bool launched;

	Default
	{
		Radius 8;
		Height 10;
		Speed 12;
		Scale 2.2;
		+NOINTERACTION
		+NOGRAVITY
	}

	void Launch(Actor goal)
	{
		tracer = goal;
		from = pos;
		dest = goal.pos + (0, 0, goal.height * 0.4);
		double d = (dest - from).Length();
		Vector3 mid = (from + dest) / 2;
		double ceil = level.PointInSector(mid.xy).ceilingplane.ZatPoint(mid.xy);
		ctrl = (mid.xy, min(max(from.z, dest.z) + d * 0.35, ceil - 20));
		A_AttachLight('flame', DynamicLight.PointLight, "FF9030", 120, 0);
		dur = int(clamp(d / 11, 42, 75));
		launched = true;
	}

	Vector3 At(double u) { return from * (1 - u) * (1 - u) + ctrl * 2 * u * (1 - u) + dest * u * u; }

	override void Tick()
	{
		Super.Tick();
		if (!launched || bDestroyed) return;
		if (tracer && tracer.health > 0) dest = tracer.pos + (0, 0, tracer.height * 0.4);
		t++;
		// Slow out of the tube, faster and faster into the dive.
		double u = clamp(t / double(dur), 0, 1);
		u = u * u * (1.6 - 0.6 * u);
		Vector3 p = At(u), ahead = At(min(u + 0.03, 1)) - p;
		if (ahead.Length() > 0.01)
		{
			angle = atan2(ahead.y, ahead.x);
			pitch = -atan2(ahead.z, ahead.xy.Length());
		}
		Vector3 back = (p - pos);
		SetOrigin(p, true);
		Trail(back);
		if (t >= dur) Impact();
	}

	// White-hot core, orange flame, long grey smoke.
	void Trail(Vector3 step)
	{
		Vector3 b = step.Length() > 0.01 ? -step.Unit() * 12 : (0, 0, 0);
		A_SpawnParticle("FFFFD0", SPF_FULLBRIGHT, 5, 10, 0, b.x, b.y, b.z, 0, 0, 0, 0, 0, 0, 1.0, -0.2);
		A_SpawnParticle("FF8A20", SPF_FULLBRIGHT, 10, 12, 0, b.x, b.y, b.z, frandom(-.5, .5), frandom(-.5, .5), frandom(-.5, .5), 0, 0, 0, 0.9, -0.09);
		for (int i = 0; i < 3; i++)
		{
			Vector3 o = -step * (i / 3.) + b;
			A_SpawnParticle(random(0, 1) ? "8A8A8A" : "606060", 0, random(55, 85), frandom(9, 14), 0,
				o.x, o.y, o.z, frandom(-.3, .3), frandom(-.3, .3), frandom(0, .5), 0, 0, 0, 0.7, -0.009, 0.3);
		}
	}

	void Impact()
	{
		let fx = Spawn("CatExplosion", pos, ALLOW_REPLACE);
		if (fx) fx.target = target;
		A_StopSound(CHAN_BODY);
		A_Explode(260, 260, 0, true, 40, 0, 0, "", 'Explosive');
		let w = Spawn("WhiskersLanding", pos + (0, 0, 8), ALLOW_REPLACE);
		if (w) { w.vel = (frandom(-2, 2), frandom(-2, 2), 10); w.target = target; }
		MW2Handler.Get().PredatorDone(self);
		Destroy();
	}

	States
	{
	Spawn:
		PMSL A 1 Bright;
		Loop;
	}
}

// Mr. Whiskers after the impact: thrown up by the blast, he lands on his feet, sits, takes a bow, and leaves.
class WhiskersLanding : Actor
{
	Default
	{
		Radius 10;
		Height 24;
		Gravity 0.6;
		+NOBLOCKMAP
		+DROPOFF
		+NOTELEPORT
		Scale 1.0;
	}

	States
	{
	Spawn:
		WHSK A 1 { if (pos.z <= floorz + 0.5 && vel.z <= 0) return ResolveState("Landed"); return ResolveState(null); }
		Loop;
	Landed:
		WHSK B 0 A_StartSound("kitten/sight", CHAN_VOICE, 0, 1.0, 0.8);
		WHSK B 70 { MW2Handler.Get().Popup("MR. WHISKERS LANDED ON HIS FEET", Color(255, 120, 220, 255)); }
		WHSK B 35;
		TNT1 A 0 A_SpawnItemEx("TeleportFog");
		Stop;
	}
}
