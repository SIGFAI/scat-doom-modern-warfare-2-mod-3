// The demo's stage manager (demo.cfg: summon MW2Director). Console waits in demo.cfg also tick during startup,
// before the map exists, so the timeline runs here on level time instead: squads fast-rope in front of the
// player, Doom demons join the fight, and each killstreak is topped up if the pilot has not earned it yet.
class MW2Director : Actor
{
	int t0;

	Default
	{
		+NOINTERACTION
		+NOBLOCKMAP
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		t0 = level.maptime;
	}

	void Squad(int n) { KittenSquad.Insert("ShadowKitten", n, true); }
	void Demons(Class<Actor> cls, int n) { KittenSquad.Insert(cls, n, false, 380, 700); }

	override void Tick()
	{
		Super.Tick();
		int t = level.maptime - t0;
		if (t % 35) return;
		let h = MW2Handler.Get();
		if (!h) return;
		switch (t / 35)
		{
		case 1:  KittenSquad.Insert("ShadowKitten", 2, true, 230, 400); break;
		case 6:  Squad(2); break;
		case 11: h.Force(3); break;
		case 13: Squad(3); break;
		case 19: h.Force(5); break;
		case 20: Squad(3); break;
		case 29: Squad(2); Demons("DoomImp", 2); break;
		case 33: h.Force(7); break;
		case 38: KittenSquad.Insert("JuggerNyaut", 1, false, 240, 420); break;
		case 44: Squad(1); break;
		case 49: Squad(3); Demons("DoomImp", 1); break;
		case 53: h.Force(3); break;
		case 58: Squad(3); break;
		case 61: h.Force(5); break;
		case 62: Squad(2); break;
		case 70: Squad(2); Demons("Demon", 1); break;
		case 74: h.Force(7); break;
		}
	}
}

// Test stages for one killstreak at a time (summon MW2TestCare / MW2TestPred).
class MW2TestCare : MW2Director
{
	override void Tick()
	{
		int t = level.maptime - t0;
		if (t == 35) Squad(3);
		if (t == 35 * 4) MW2Handler.Get().Force(5);
		if (t == 35 * 5) Squad(2);
	}
}

class MW2TestPred : MW2Director
{
	override void Tick()
	{
		int t = level.maptime - t0;
		if (t == 35) { Squad(3); Demons("DoomImp", 2); }
		if (t == 35 * 4) MW2Handler.Get().predPending = gametic;
		if (t == 35 * 9) Demons("JuggerNyaut", 1);
	}
}

class MW2TestJug : MW2Director
{
	override void Tick()
	{
		int t = level.maptime - t0;
		if (t == 35) KittenSquad.Insert("JuggerNyaut", 1, false, 260, 420);
	}
}
