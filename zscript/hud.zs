// Modern Warfare flavour on top of Doom: hitmarkers, +100 popups, killstreaks called in by the SuperIntelligent
// Cat (General Shepurrd) over the radio, a minimap that shows every enemy while the UAV flies, the mission intro
// card and the Predator missile-cam. Play code keeps the state; the UI part (further down) draws it.
class MW2Popup
{
	String text;
	int at;
	Color col;
}

class MW2Handler : EventHandler
{
	const UAV_TICS = 35 * 30;
	const OBJECTIVE = 25;     // Shadow Kittens to neutralize before General Shepurrd shows his true colours

	int hitAt, killHitAt;     // last hitmarker (gametic), last hit that killed
	int kills, streak;        // player kills, kills toward the next killstreak (resets after the Predator)
	Array<MW2Popup> popups;
	String bigText, bigSub;
	int bigAt;
	Color bigCol;
	String radioText;
	int radioAt, radioLen;
	String laterText;
	Sound laterSound;
	int laterAt, laterLen;
	int uavUntil, predPending, introAt, predEndAt;
	bool gotUAV, gotCare; Actor pred;   // the Predator in flight
	int kittensDown, doneAt;
	// Minimap blips, relative to the player: x, y, and 1 when the UAV (or its own gunfire) reveals it.
	Array<double> blipX, blipY;
	Array<int> blipShown;

	static MW2Handler Get() { return MW2Handler(EventHandler.Find("MW2Handler")); }

	clearscope PlayerPawn PlayerActor() { return players[consoleplayer].mo; }

	static bool IsPlayerSide(Actor a)
	{
		if (!a) return false;
		if (a.player) return true;
		return a.bFriendly || (a.target && a.target.player && !a.bIsMonster);
	}

	void Popup(String text, Color col = Color(255, 255, 230, 120))
	{
		let p = new("MW2Popup");
		p.text = text;
		p.at = gametic;
		p.col = col;
		popups.Push(p);
		if (popups.Size() > 4) popups.Delete(0);
	}

	void Banner(String text, String sub, Color col = Color(255, 255, 220, 90))
	{
		bigText = text;
		bigSub = sub;
		bigAt = gametic;
		bigCol = col;
		let mo = PlayerActor();
		if (mo) mo.A_StartSound("ks/earned", CHAN_7, CHANF_OVERLAP, 1.0, ATTN_NONE);
	}

	// General Shepurrd on the radio: portrait, subtitle, voice.
	void Say(String text, Sound snd, int tics = 105)
	{
		radioText = text;
		radioAt = gametic;
		radioLen = tics;
		let mo = PlayerActor();
		if (!mo) return;
		mo.A_StartSound("radio/click", CHAN_6, CHANF_OVERLAP, 0.6, ATTN_NONE);
		mo.A_StartSound(snd, CHAN_5, 0, 1.0, ATTN_NONE);
	}

	void SayLater(String text, Sound snd, int delay, int tics = 105)
	{
		laterText = text;
		laterSound = snd;
		laterAt = gametic + delay;
		laterLen = tics;
	}

	override void WorldLoaded(WorldEvent e)
	{
		introAt = gametic;
		SayLater("Task Furce 141, Shepurrd here. My IQ is 9000. Theirs is 'cat'. Engage.", "sic/intro", 30, 315);
	}

	override void PlayerEntered(PlayerEvent e)
	{
		let mo = players[e.PlayerNumber].mo;
		if (!mo) return;
		mo.GiveInventory("Purrbine", 1);
		mo.GiveInventory("Clip", 200);
		mo.player.PendingWeapon = Weapon(mo.FindInventory("Purrbine"));
	}

	override void WorldThingDamaged(WorldEvent e)
	{
		if (!e.Thing || !e.Thing.bIsMonster || e.Damage <= 0) return;
		if (!IsPlayerSide(e.DamageSource)) return;
		hitAt = gametic;
		if (e.Thing.health <= 0) killHitAt = gametic;
		let mo = PlayerActor();
		if (mo) mo.A_StartSound("hud/hitmark", CHAN_7, CHANF_OVERLAP, 0.8, ATTN_NONE);
	}

	override void WorldThingDied(WorldEvent e)
	{
		let t = e.Thing;
		if (!t || t.bFriendly) return;
		if (t is "ShadowKitten" && ++kittensDown == OBJECTIVE) MissionComplete();
		if (!t.bIsMonster) return;
		if (!IsPlayerSide(t.target) && !IsPlayerSide(e.Inflictor)) return;
		kills++;
		// As in Modern Warfare, killstreak kills do not count toward the next killstreak.
		bool byStreak = e.Inflictor is "CatExplosion" || e.Inflictor is "CarePackage" || e.Inflictor is "PredatorMissile";
		if (!byStreak) streak++;
		if (!(t is "JuggerNyaut")) Popup(t is "ShadowKitten" ? "+100  ENEMY KITTY DOWN" : "+100  DEMON DOWN");
		CheckStreak();
	}

	// Each streak once per cycle; the Predator closes the cycle and the ladder starts again.
	void CheckStreak()
	{
		if (streak >= 3 && !gotUAV) { gotUAV = true; CallUAV(); }
		if (streak >= 5 && !gotCare) { gotCare = true; CallCarePackage(); }
		if (streak >= 7) { streak = 0; gotUAV = gotCare = false; predPending = gametic; }
	}

	// The demo director tops up a streak the pilot has not reached in time.
	void Force(int n)
	{
		if (n >= 7 && (pred || predPending || (predEndAt && gametic - predEndAt < 35 * 15))) return;
		if (n == 5 && gotCare) return;
		if (n == 3 && gotUAV) return;
		if (streak < n) streak = n;
		CheckStreak();
	}

	// Test hooks: "netevent mw2_uav", "netevent mw2_care", "netevent mw2_pred" call a killstreak right away.
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name ~== "mw2_uav") Force(3);
		else if (e.Name ~== "mw2_care") Force(5);
		else if (e.Name ~== "mw2_pred") Force(7);
	}

	override void WorldTick()
	{
		let mo = PlayerActor();
		if (!mo) return;
		if (laterAt && gametic >= laterAt)
		{
			laterAt = 0;
			Say(laterText, laterSound, laterLen);
		}
		if (predPending && gametic >= predPending && !pred) TryPredator(mo);
		if (pred && pred.bDestroyed) pred = null;
		if (gametic % 3 == 0) ScanBlips(mo);
		// Supply drops keep Task Furce 141 in rifle ammo.
		if (gametic % 35 == 0 && mo.CountInv("Clip") < 50) mo.GiveInventory("Clip", 60);
	}

	void ScanBlips(PlayerPawn mo)
	{
		blipX.Clear();
		blipY.Clear();
		blipShown.Clear();
		bool uav = gametic < uavUntil;
		let it = ThinkerIterator.Create("Actor"); Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bIsMonster || a.health <= 0 || a.bFriendly) continue;
			Vector2 d = mo.Vec2To(a);
			if (d.Length() > 1400) continue;
			let k = ShadowKitten(a);
			bool fired = k && level.maptime - k.firedAt < 35;
			blipX.Push(d.x);
			blipY.Push(d.y);
			blipShown.Push(uav || fired ? 1 : 0);
		}
	}

	void CallUAV()
	{
		let mo = PlayerActor();
		if (!mo) return;
		let d = Actor.Spawn("UAVDrone", mo.pos + (0, 0, 60), ALLOW_REPLACE);
		if (d) d.target = mo;
		uavUntil = gametic + UAV_TICS;
		Banner("UAV ONLINE", "3 KILLSTREAK: enemy kitties revealed on the minimap");
		Say("UAV online. I see everything. I always have.", "sic/uav", 185);
	}

	void CallCarePackage()
	{
		let mo = PlayerActor();
		if (!mo) return;
		// In front of the player, short of the nearest wall, dropped from the ceiling.
		FLineTraceData tr;
		// Straight down the player's line of fire, short of the wall and of the enemy he is fighting, so it lands in view.
		double dist = 260, ba = mo.angle;
		if (mo.LineTrace(ba, 400, 0, TRF_THRUACTORS, 24, data: tr)) dist = clamp(tr.Distance - 64, 128, 260);
		FLineTraceData hit;
		if (mo.LineTrace(ba, 400, 0, 0, 24, data: hit) && hit.HitType == TRACE_HitActor) dist = clamp(min(dist, hit.Distance - 72), 128, 260);
		Vector2 xy = mo.Vec2Angle(dist, ba);
		let sec = level.PointInSector(xy);
		double fz = sec.floorplane.ZatPoint(xy), cz = sec.ceilingplane.ZatPoint(xy);
		let box = Actor.Spawn("CarePackage", (xy, min(cz - 44, fz + 360)), ALLOW_REPLACE);
		if (box) box.target = mo;
		mo.A_StartSound("ks/jet", CHAN_BODY, CHANF_OVERLAP, 1.0, ATTN_NONE);
		Banner("CARE PACKAGE", "5 KILLSTREAK: a cardboard box. For them.");
		Say("Care package inbound. Do not open it. It is not for you.", "sic/care", 170);
	}

	// The Predator goes for the biggest visible group of enemies; with nobody around it waits.
	void TryPredator(PlayerPawn mo)
	{
		double bestScore = -1; Actor best = null;
		let it = ThinkerIterator.Create("Actor"); Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bIsMonster || a.health <= 0 || a.bFriendly || a.bInvisible) continue;
			double d = mo.Distance2D(a);
			if (d > 2200 || d < 96) continue;
			if (!mo.CheckSight(a)) continue;
			double score = 1;
			let it2 = ThinkerIterator.Create("Actor"); Actor b;
			while (b = Actor(it2.Next()))
				if (b != a && b.bIsMonster && b.health > 0 && a.Distance2D(b) < 320) score += 1;
			if (score > bestScore) { bestScore = score; best = a; }
		}
		if (!best) { predPending = gametic + 20; return; }
		predPending = 0;
		double top = min(mo.ceilingz - mo.pos.z - 14, 92);
		Vector3 from = mo.pos + (Actor.AngleToVector(mo.angle, 36) + Actor.AngleToVector(mo.angle - 90, 8), top);
		let m = Actor.Spawn("PredatorMissile", from, ALLOW_REPLACE);
		if (!m) return;
		m.target = mo;
		PredatorMissile(m).Launch(best);
		m.A_StartSound("pred/fly", CHAN_BODY, CHANF_LOOPING, 1.0, 0.5);
		pred = m;
		TexMan.SetCameraToTexture(m, "PREDCAM", 70);
		Banner("PREDATOR MISSILE", "7 KILLSTREAK: Mr. Whiskers volunteered", Color(255, 255, 90, 60));
		Say("Predator missile away! Mr. Whiskers volunteered. Mostly.", "sic/pred", 150);
		mo.A_StartSound("pred/incoming", CHAN_AUTO, CHANF_OVERLAP, 0.8, ATTN_NONE);
	}

	// The twist, Modern Warfare style: the general was never on your side. He just wanted the box.
	void MissionComplete()
	{
		doneAt = gametic;
		Banner("MISSION ACCOMPLISHED", "Shadow Kitten Company neutralized", Color(255, 120, 255, 120));
		SayLater("Excellent work, Sergeant. One more thing... the box. Give me the box. It is MY box now.", "sic/betray", 110, 260);
	}

	void PredatorDone(Actor m)
	{
		if (pred == m) pred = null;
		predEndAt = gametic;
		SayLater("He landed on his feet. Obviously.", "sic/feet", 50, 95);
	}
}

// What the player sees, drawn every frame from the handler's state. Virtual 960x540 units, scaled to the screen.
extend class MW2Handler
{
	ui double S() { return Screen.GetHeight() / 540.; }

	ui void Txt(Font f, String s, double x, double y, Color c, double scale = 1., double alpha = 1., bool center = false)
	{
		double k = S() * scale;
		if (center) x -= f.StringWidth(s) * k / 2;
		Screen.DrawText(f, Font.CR_WHITE, x, y, s, DTA_ScaleX, k, DTA_ScaleY, k, DTA_Alpha, alpha, DTA_Color, c);
	}

	ui void Icon(String sprite, double x, double y, double w, double h, double alpha = 1.)
	{
		TextureID tex = TexMan.CheckForTexture(sprite, TexMan.Type_Any);
		if (!tex.IsValid()) return;
		Vector2 sz = TexMan.GetScaledSize(tex);
		double f = min(w / sz.x, h / sz.y);
		Screen.DrawTexture(tex, false, x + (w - sz.x * f) / 2, y + (h - sz.y * f) / 2, DTA_DestWidthF, sz.x * f, DTA_DestHeightF, sz.y * f,
			DTA_LeftOffset, 0, DTA_TopOffset, 0, DTA_Alpha, alpha);
	}

	// Liang-Barsky: clips the segment to the box; false when nothing is left.
	ui bool Clip(double x0, double y0, double x1, double y1, double minx, double miny, double maxx, double maxy,
		out double ax, out double ay, out double bx, out double by)
	{
		double t0 = 0, t1 = 1, dx = x1 - x0, dy = y1 - y0;
		double p[4], q[4];
		p[0] = -dx; q[0] = x0 - minx;
		p[1] = dx;  q[1] = maxx - x0;
		p[2] = -dy; q[2] = y0 - miny;
		p[3] = dy;  q[3] = maxy - y0;
		for (int i = 0; i < 4; i++)
		{
			if (p[i] == 0) { if (q[i] < 0) return false; continue; }
			double r = q[i] / p[i];
			if (p[i] < 0) { if (r > t1) return false; if (r > t0) t0 = r; }
			else { if (r < t0) return false; if (r < t1) t1 = r; }
		}
		ax = x0 + t0 * dx; ay = y0 + t0 * dy;
		bx = x0 + t1 * dx; by = y0 + t1 * dy;
		return true;
	}

	ui void Minimap(PlayerPawn mo, double k, int now)
	{
		double size = 168 * k, x0 = 14 * k, y0 = 14 * k;
		double cx = x0 + size / 2, cy = y0 + size / 2;
		double range = 1100, sc = (size / 2) / range;
		bool uav = now < uavUntil;
		Screen.Dim(Color(0, 26, 14), 0.62, int(x0), int(y0), int(size), int(size));
		double ang = mo.angle;
		Vector2 f = Actor.AngleToVector(ang, 1), r = Actor.AngleToVector(ang - 90, 1);
		Vector2 ppos = mo.pos.xy;
		Color wall = Color(255, 150, 220, 160);
		for (int i = 0; i < level.lines.Size(); i++)
		{
			Line l = level.lines[i];
			bool solid = !(l.flags & Line.ML_TWOSIDED) || !l.backsector
				|| abs(l.frontsector.floorplane.ZatPoint(l.v1.p) - l.backsector.floorplane.ZatPoint(l.v1.p)) > 24;
			if (!solid) continue;
			Vector2 a = l.v1.p - ppos, b = l.v2.p - ppos;
			if (min(a.Length(), b.Length()) > range * 1.6 && (a - b).Length() < range) continue;
			double ax = cx + (a dot r) * sc, ay = cy - (a dot f) * sc;
			double bx = cx + (b dot r) * sc, by = cy - (b dot f) * sc;
			double qx, qy, sx, sy;
			if (Clip(ax, ay, bx, by, x0, y0, x0 + size, y0 + size, qx, qy, sx, sy))
				Screen.DrawThickLine(int(qx), int(qy), int(sx), int(sy), 1.6 * k, wall, 210);
		}
		// UAV sweep: a bright arm turning around the player.
		if (uav)
		{
			double sw = now * 6.;
			double ex = cx + cos(sw) * size * 0.7, ey = cy + sin(sw) * size * 0.7;
			double qx, qy, sx, sy;
			if (Clip(cx, cy, ex, ey, x0, y0, x0 + size, y0 + size, qx, qy, sx, sy))
				Screen.DrawThickLine(int(qx), int(qy), int(sx), int(sy), 3 * k, Color(255, 90, 255, 120), 150);
		}
		// Enemies: red squares, only those the UAV (or their own gunfire) gives away.
		for (int i = 0; i < blipX.Size(); i++)
		{
			if (!blipShown[i]) continue;
			Vector2 d = (blipX[i], blipY[i]);
			double bx = cx + (d dot r) * sc, by = cy - (d dot f) * sc;
			if (bx < x0 + 3 * k || by < y0 + 3 * k || bx > x0 + size - 3 * k || by > y0 + size - 3 * k) continue;
			double s = (5 + (now % 18 < 9 ? 1 : 0)) * k;
			Screen.Dim(Color(255, 40, 30), 1.0, int(bx - s / 2), int(by - s / 2), int(s), int(s));
		}
		// The player: a yellow arrow pointing up.
		Color yl = Color(255, 255, 230, 60);
		Screen.DrawThickLine(int(cx), int(cy - 8 * k), int(cx - 6 * k), int(cy + 6 * k), 2 * k, yl);
		Screen.DrawThickLine(int(cx), int(cy - 8 * k), int(cx + 6 * k), int(cy + 6 * k), 2 * k, yl);
		Screen.DrawThickLine(int(cx - 6 * k), int(cy + 6 * k), int(cx + 6 * k), int(cy + 6 * k), 2 * k, yl);
		// Frame and label.
		Color fr = Color(255, 120, 200, 140);
		Screen.DrawThickLine(int(x0), int(y0), int(x0 + size), int(y0), 2 * k, fr);
		Screen.DrawThickLine(int(x0), int(y0 + size), int(x0 + size), int(y0 + size), 2 * k, fr);
		Screen.DrawThickLine(int(x0), int(y0), int(x0), int(y0 + size), 2 * k, fr);
		Screen.DrawThickLine(int(x0 + size), int(y0), int(x0 + size), int(y0 + size), 2 * k, fr);
		if (uav) Txt(NewSmallFont, String.Format("UAV ONLINE  %ds", (uavUntil - now) / 35), x0 + 6 * k, y0 + size + 4 * k, Color(255, 120, 255, 140));
		// Objective tracker.
		double oy = y0 + size + 22 * k;
		if (!doneAt)
		{
			Txt(NewSmallFont, "OBJECTIVE", x0, oy, Color(255, 255, 220, 90), 1.0);
			Txt(NewSmallFont, String.Format("Neutralize Shadow Kittens  %d/%d", kittensDown, OBJECTIVE), x0, oy + 13 * k, Color(255, 235, 235, 235), 1.0);
		}
		else if (now - doneAt > 380)
		{
			Txt(NewSmallFont, "NEW OBJECTIVE", x0, oy, Color(255, 255, 90, 60), 1.0);
			Txt(NewSmallFont, "Take the box back from Gen. Shepurrd", x0, oy + 13 * k, Color(255, 235, 235, 235), 1.0);
		}
		else Txt(NewSmallFont, "OBJECTIVE COMPLETE", x0, oy, Color(255, 120, 255, 120), 1.0);
	}

	ui void Ladder(double w, double k)
	{
		static const int NEED[] = { 3, 5, 7 };
		static const String NAMES[] = { "UAV", "CARE PACKAGE", "PREDATOR MISSILE" };
		static const String ICONS[] = { "UAVDA0", "CBOXA0", "PMSLA7A3" };
		double x = w - 210 * k, y = 150 * k;
		Txt(NewSmallFont, String.Format("KILLSTREAK  %d", streak), x, y - 22 * k, Color(255, 255, 255, 255), 1.15);
		for (int i = 0; i < 3; i++)
		{
			bool got = streak >= NEED[i] || (i == 2 && (pred || predPending));
			double yy = y + i * 40 * k;
			Screen.Dim(got ? Color(120, 90, 20) : Color(0, 0, 0), got ? 0.55 : 0.4, int(x - 4 * k), int(yy - 2 * k), int(204 * k), int(36 * k));
			Icon(ICONS[i], x, yy, 48 * k, 32 * k, got ? 1. : 0.45);
			Color c = got ? Color(255, 255, 220, 70) : Color(255, 170, 170, 170);
			Txt(NewSmallFont, String.Format("%d", NEED[i]), x + 54 * k, yy + 9 * k, c, 1.1);
			Txt(NewSmallFont, NAMES[i], x + 72 * k, yy + 9 * k, c, 1.0);
		}
	}

	ui void Radio(double k, int now)
	{
		int age = now - radioAt;
		if (!radioAt || age > radioLen) return;
		double a = age > radioLen - 12 ? (radioLen - age) / 12. : 1.;
		double ps = 70 * k, x = 14 * k, y = Screen.GetHeight() - 150 * k;
		Screen.Dim(Color(0, 18, 10), 0.6 * a, int(x), int(y), int(400 * k), int(ps + 8 * k));
		bool talking = age < radioLen * 0.7 && (now / 4) % 2 == 0;
		Icon(talking ? "SICAT2" : "SICAT1", x + 4 * k, y + 4 * k, ps, ps, a);
		Txt(NewSmallFont, "GEN. SHEPURRD", x + ps + 14 * k, y + 8 * k, Color(255, 120, 255, 140), 1.15, a);
		Txt(NewSmallFont, "SuperIntelligent Cat", x + ps + 14 * k + NewSmallFont.StringWidth("GEN. SHEPURRD  ") * 1.15 * k, y + 8 * k, Color(255, 150, 190, 150), 0.95, a);
		// Typewriter subtitle, wrapped.
		int chars = min(radioText.Length(), age * 2);
		String shown = radioText.Left(chars);
		BrokenLines bl = NewSmallFont.BreakLines(shown, 270);
		for (int i = 0; i < bl.Count(); i++)
			Txt(NewSmallFont, bl.StringAt(i), x + ps + 14 * k, y + (28 + i * 15) * k, Color(255, 240, 240, 230), 1.05, a);
	}

	ui void Intro(double h, double k, int now)
	{
		static const String LINES[] = { "'Operation Hairball'", "Day 1 - 06:42:13", "Sgt. 'Roach' McFluff", "Task Furce 141", "Hydroelectric Plant, Mars" };
		int age = now - introAt;
		if (age > 35 * 9) return;
		double a = age > 35 * 8 ? 1. - (age - 35 * 8) / 35. : 1.;
		double right = Screen.GetWidth() - 30 * k, y = h - 180 * k;
		for (int i = 0; i < 5; i++)
		{
			int start = 10 + i * 18;
			if (age < start) break;
			String s = LINES[i];
			double sc = i == 0 ? 2.0 : 1.25;
			double full = NewSmallFont.StringWidth(s) * sc * k;
			s = s.Left(min(s.Length(), (age - start) * 2));
			Txt(NewSmallFont, s, right - full, y + (i == 0 ? 0 : 16 + i * 20) * k, i == 0 ? Color(255, 255, 255, 255) : Color(255, 200, 235, 200), sc, a);
		}
	}

	ui void PredCam(double w, double k, int now)
	{
		bool lost = !pred && predEndAt && now - predEndAt < 30;
		if (!pred && !lost) return;
		double cw = 300 * k, ch = 188 * k, x = w / 2 - cw / 2, y = 12 * k;
		if (lost)
		{
			// Signal lost: static noise after the impact.
			Screen.Dim(Color(0, 0, 0), 0.85, int(x), int(y), int(cw), int(ch));
			for (int i = 0; i < 140; i++)
			{
				int g = Random[noise](60, 230);
				Screen.Dim(Color(g, g, g), 0.9, int(x + FRandom[noise](0, cw - 6 * k)), int(y + FRandom[noise](0, ch - 3 * k)), int(6 * k), int(3 * k));
			}
			Txt(NewSmallFont, "SIGNAL LOST", x + cw / 2, y + ch / 2 - 10 * k, Color(255, 255, 255, 255), 1.6, 1., true);
			return;
		}
		TextureID tex = TexMan.CheckForTexture("PREDCAM", TexMan.Type_Any);
		if (tex.IsValid())
			Screen.DrawTexture(tex, false, x, y, DTA_DestWidthF, cw, DTA_DestHeightF, ch, DTA_Desaturate, 255);
		// Thermal grain over the feed.
		for (int i = 0; i < 40; i++)
		{
			int g = Random[noise](90, 200);
			Screen.Dim(Color(g, g, g), 0.25, int(x + FRandom[noise](0, cw - 4 * k)), int(y + FRandom[noise](0, ch - 2 * k)), int(4 * k), int(2 * k));
		}
		Color c = Color(255, 230, 230, 230);
		double b = 22 * k;
		// Corner brackets, centre reticle, label.
		Screen.DrawThickLine(int(x), int(y), int(x + b), int(y), 2 * k, c);
		Screen.DrawThickLine(int(x), int(y), int(x), int(y + b), 2 * k, c);
		Screen.DrawThickLine(int(x + cw), int(y), int(x + cw - b), int(y), 2 * k, c);
		Screen.DrawThickLine(int(x + cw), int(y), int(x + cw), int(y + b), 2 * k, c);
		Screen.DrawThickLine(int(x), int(y + ch), int(x + b), int(y + ch), 2 * k, c);
		Screen.DrawThickLine(int(x), int(y + ch), int(x), int(y + ch - b), 2 * k, c);
		Screen.DrawThickLine(int(x + cw), int(y + ch), int(x + cw - b), int(y + ch), 2 * k, c);
		Screen.DrawThickLine(int(x + cw), int(y + ch), int(x + cw), int(y + ch - b), 2 * k, c);
		double mx = x + cw / 2, my = y + ch / 2;
		Screen.DrawThickLine(int(mx - 14 * k), int(my), int(mx + 14 * k), int(my), 2 * k, c);
		Screen.DrawThickLine(int(mx), int(my - 14 * k), int(mx), int(my + 14 * k), 2 * k, c);
		if ((now / 8) % 2) Txt(NewSmallFont, "PREDATOR - MISSILE CAM", x + 8 * k, y + ch - 20 * k, Color(255, 255, 80, 60), 1.0);
	}

	override void RenderOverlay(RenderEvent e)
	{
		let mo = PlayerActor();
		if (!mo || automapactive) return;
		double w = Screen.GetWidth(), h = Screen.GetHeight(), k = S();
		double cx = w / 2, cy = h / 2;
		int now = gametic;

		Minimap(mo, k, now);
		Ladder(w, k);
		Radio(k, now);
		Intro(h, k, now);
		PredCam(w, k, now);

		// Hitmarker: four short white strokes around the crosshair, red when the hit killed.
		int age = now - hitAt;
		if (hitAt && age < 9)
		{
			double a = 1. - age / 9.;
			bool kill = now - killHitAt < 9;
			Color c = kill ? Color(255, 255, 60, 40) : Color(255, 255, 255, 255);
			double g = 7 * k, l = (kill ? 17 : 13) * k + age * 0.6 * k;
			for (int i = 0; i < 4; i++)
			{
				double sx = (i & 1) ? 1 : -1, sy = (i & 2) ? 1 : -1;
				Screen.DrawThickLine(int(cx + sx * g), int(cy + sy * g), int(cx + sx * l), int(cy + sy * l), 2.6 * k, c, int(255 * a));
			}
		}

		// +100 popups, stacked under the crosshair, rising and fading.
		for (int i = 0; i < popups.Size(); i++)
		{
			let p = popups[i];
			int pa = now - p.at;
			if (pa > 70) continue;
			double a = pa < 50 ? 1. : 1. - (pa - 50) / 20.;
			double y = cy + 56 * k + (popups.Size() - 1 - i) * 19 * k - min(pa, 12) * 0.7 * k;
			Txt(NewSmallFont, p.text, cx, y, p.col, 1.1, a, true);
		}

		// Big banner: killstreak earned.
		int ba = now - bigAt;
		if (bigAt && ba < 105)
		{
			double a = ba < 85 ? 1. : 1. - (ba - 85) / 20.;
			double pop = ba < 6 ? 1.6 - ba * 0.1 : 1.;
			double by = (pred || (predEndAt && now - predEndAt < 30)) ? cy - 30 * k : cy - 130 * k;
			Txt(NewSmallFont, bigText, cx, by, bigCol, 3.0 * pop, a, true);
			Txt(NewSmallFont, bigSub, cx, by + 46 * k, Color(255, 235, 235, 235), 1.2, a, true);
		}
	}
}
