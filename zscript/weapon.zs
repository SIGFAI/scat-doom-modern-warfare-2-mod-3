// The player's rifle, the "M4 Purrbine": red-dot sight, held by cat paws. Hitscan with a visible tracer,
// brass flying out to the right, a recoil kick on the sprite.
class Purrbine : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 400;
		Weapon.SlotNumber 4;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 60;
		Weapon.AmmoType "Clip";
		Weapon.Kickback 60;
		Inventory.PickupMessage "You got the M4 Purrbine!";
		Obituary "%o was purr-forated by %k's M4 Purrbine.";
		Tag "M4 Purrbine";
		AttackSound "rifle/fire";
		+WEAPON.NOAUTOFIRE
	}

	action void A_PurrShot()
	{
		A_StartSound("rifle/fire", CHAN_WEAPON, CHANF_OVERLAP, 0.9);
		A_FireBullets(2.2, 1.2, 1, 3 * random(1, 3), "RiflePuff", FBF_USEAMMO | FBF_NORANDOM);
		A_GunFlash();
		A_WeaponOffset(frandom(2, 5), 32 + frandom(4, 7));
		// Brass: a few hot gold flecks thrown out to the right of the gun.
		Vector2 side = Actor.AngleToVector(angle - 90, 14) + Actor.AngleToVector(angle, 10);
		for (int i = 0; i < 2; i++)
		{
			Vector2 v = Actor.AngleToVector(angle - 90 + frandom(-20, 20), frandom(3, 5));
			A_SpawnParticle("E8B840", 0, 22, 2.5, 0, side.x, side.y, height * 0.62,
				v.x, v.y, frandom(2, 4), 0, 0, -0.6, 1.0, -0.02);
		}
	}

	States
	{
	Ready:
		CRIF A 1 A_WeaponReady;
		Loop;
	Deselect:
		CRIF A 1 A_Lower(12);
		Loop;
	Select:
		CRIF A 1 A_Raise(12);
		Loop;
	Fire:
		CRIF B 2 Bright A_PurrShot;
		CRIF A 1 A_WeaponOffset(0, 32, WOF_INTERPOLATE);
		CRIF A 1;
		CRIF A 0 A_ReFire;
		Goto Ready;
	Flash:
		TNT1 A 2 A_Light2;
		TNT1 A 1 A_Light0;
		Stop;
	Spawn:
		CRIF A -1;
		Stop;
	}
}

// Bullet impact: sparks and a dust puff on walls, and a bright tracer line drawn back to the shooter.
class RiflePuff : BulletPuff
{
	Default
	{
		+PUFFGETSOWNER
		+PUFFONACTORS
		+ALWAYSPUFF
		VSpeed 0.5;
		RenderStyle "Translucent";
		Alpha 0.8;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		if (target)
		{
			// Muzzle in front of the shooter's eyes, a bit right and down, like the red-dot rifle on screen.
			Vector3 from = target.pos + (Actor.AngleToVector(target.angle, 24) + Actor.AngleToVector(target.angle - 90, 6), target.height * 0.72);
			Vector3 d = pos - from;
			double len = d.Length();
			int n = clamp(int(len / 12), 2, 120);
			for (int i = 1; i < n; i++)
			{
				Vector3 p = from + d * (double(i) / n) - pos;
				A_SpawnParticle(i > n - 4 ? "FFFFE0" : "FFC040", SPF_FULLBRIGHT, 3, 2.0, 0, p.x, p.y, p.z,
					0, 0, 0, 0, 0, 0, 0.9, -0.3);
			}
		}
		if (!tracer) CatFx.Sparks(self, 5, "FFD860");
	}
}
