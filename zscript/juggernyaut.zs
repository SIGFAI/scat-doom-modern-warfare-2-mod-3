// JuggerNyaut: a cat in a bomb-disposal suit with a minigun. Slow, armored (bullets spark off it), long bursts
// of tracers. When the suit finally breaks, it is empty but for one tiny kitten, who runs for it.
class JuggerNyaut : Actor
{
	Default
	{
		Health 300;
		Scale 1.15;
		Height 84;
		Radius 30;
		Mass 800;
		Speed 6;
		PainChance 50;
		Monster;
		+FLOORCLIP
		+NOBLOOD
		SeeSound "kitten/death";
		PainSound "kitten/pain";
		DeathSound "kitten/death";
		ActiveSound "kitten/sight";
		Obituary "%o was flattened by a JuggerNyaut.";
		Tag "JuggerNyaut";
		MinMissileChance 120;
	}

	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		int dealt = Super.DamageMobj(inflictor, source, damage, mod, flags, angle);
		if (dealt > 0)
		{
			CatFx.Sparks(self, 8, "FFE070");
			if (!random(0, 2)) A_StartSound("hud/hitmark", CHAN_BODY, CHANF_OVERLAP, 0.5, 1.5);
		}
		return dealt;
	}

	void MinigunShot()
	{
		A_StartSound("kitten/rifle", CHAN_WEAPON, CHANF_OVERLAP, 0.9);
		A_SpawnProjectile("CatTracer", 30, 10, frandom(-6, 6), CMF_OFFSETPITCH, frandom(-2, 2));
	}

	void TinyEscape()
	{
		let k = Spawn("TinyKitten", pos + (0, 0, height - 10), ALLOW_REPLACE);
		if (k)
		{
			// Away from whoever killed it.
			double a = target ? AngleTo(target) + 180 + frandom(-30, 30) : frandom(0, 360);
			k.angle = a;
			k.vel = (Actor.AngleToVector(a, 4), 6);
		}
		MW2Handler.Get().Popup("+300  JUGGERNYAUT DOWN... it was a tiny kitten", Color(255, 255, 140, 60));
	}

	States
	{
	Spawn:
		JUGN A 10 A_Look;
		Loop;
	See:
		JUGN AABB 5 A_Chase;
		Loop;
	Missile:
		JUGN A 12 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 2 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 2 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 2 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 2 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 2 A_FaceTarget;
		JUGN E 2 Bright MinigunShot;
		JUGN A 16;
		Goto See;
	Pain:
		JUGN F 6;
		JUGN F 8 A_Pain;
		Goto See;
	Death:
	XDeath:
		JUGN F 6 A_Scream;
		JUGN G 10 { CatFx.Sparks(self, 30, "FFD040"); A_NoBlocking(); }
		JUGN G 4 TinyEscape;
		JUGN H 6 { A_StartSound("box/thud", CHAN_BODY, 0, 1.0, 0.8); A_Quake(2, 6, 0, 300); }
		JUGN H -1;
		Stop;
	}
}

// The pilot of the JuggerNyaut: flees as fast as its tiny legs go, then vanishes around a corner.
class TinyKitten : Actor
{
	int life;

	Default
	{
		Radius 6;
		Height 14;
		Speed 12;
		Scale 1.4;
		Gravity 0.8;
		+NOBLOCKMAP
		+DROPOFF
		+NOTELEPORT
	}

	void Flee()
	{
		life++;
		if (pos.z <= floorz + 0.5)
		{
			if (!TryMove(Vec2Angle(speed, angle), 0)) angle += frandom(60, 120);
			if (life % 6 == 0) A_SpawnParticle("C0B0A0", 0, 14, 4, 0, 0, 0, 2, 0, 0, 0.4, 0, 0, 0, 0.6, -0.04);
		}
		if (life == 2) A_StartSound("kitten/sight", CHAN_VOICE, 0, 1.0, 0.8);
		if (life > 110) { Spawn("TeleportFog", pos, ALLOW_REPLACE); Destroy(); }
	}

	States
	{
	Spawn:
		TKIT AB 2 Flee;
		Loop;
	}
}
