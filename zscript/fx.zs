// Shared effects: tracer rounds, fur puffs, sparks. Everything visual here is engine particles, no art.

// A rifle round you can see: a fast invisible bullet that leaves a hot yellow streak behind it.
class CatTracer : Actor
{
	Default
	{
		Radius 3;
		Height 4;
		Speed 55;
		DamageFunction (random(2, 4));
		Projectile;
		+RANDOMIZE
		+BLOODSPLATTER
		RenderStyle "Add";
		SeeSound "";
		DeathSound "";
	}

	override void Tick()
	{
		Vector3 old = pos;
		Super.Tick();
		if (bMissile && !IsFrozen())
		{
			Vector3 d = pos - old;
			for (int i = 0; i < 6; i++)
			{
				double f = i / 6.;
				A_SpawnParticle(i < 2 ? "FFFFC0" : "FFB020", SPF_FULLBRIGHT, 4, 3.5 - f * 1.5, 0,
					-d.x * f, -d.y * f, -d.z * f, 0, 0, 0, 0, 0, 0, 1.0, -0.2);
			}
		}
	}

	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	Death:
		TNT1 A 0 { CatFx.Sparks(self, 6, "FFD060"); }
		PUFF A 3 Bright;
		PUFF BCD 3;
		Stop;
	XDeath:
		TNT1 A 1;
		Stop;
	}
}

class CatFx play
{
	// Bright sparks bursting out of a point (bullet impacts, hitmarkers on armor).
	static void Sparks(Actor at, int n, Color c)
	{
		for (int i = 0; i < n; i++)
		{
			at.A_SpawnParticle(c, SPF_FULLBRIGHT, random(8, 16), frandom(2, 3.5), frandom(0, 360),
				0, 0, 0, frandom(-4, 4), frandom(-4, 4), frandom(0, 5), 0, 0, -0.5, 1.0, -0.06);
		}
	}

	// A cloud of fur tufts in the cat's own colours: every hit on a cat shows.
	static void Fur(Actor at, int n, double zofs = 0)
	{
		static const int FUR[] = { 0xE08A30, 0xB85F1A, 0xF4C27A, 0x2A2A2A };
		for (int i = 0; i < n; i++)
		{
			at.A_SpawnParticle(FUR[random(0, 3)], 0, random(25, 45), frandom(2.5, 5), frandom(0, 360),
				frandom(-8, 8), frandom(-8, 8), zofs + frandom(-6, 6),
				frandom(-2.5, 2.5), frandom(-2.5, 2.5), frandom(0.5, 3.5), 0, 0, -0.12, 1.0, -0.025);
		}
	}
}
