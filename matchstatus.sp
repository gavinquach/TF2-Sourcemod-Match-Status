// Force semicolon
#pragma semicolon 1

// English references for Teams (from PUGMod)
#define SPECTATOR 1
#define RED 2
#define BLU 3

// Includes
#include <sourcemod>
#include <tf2>					// TF enums and TF2_ functions
#include <tf2_stocks>			// more TF2_ functions
#include <morecolors>			// Colored chat printouts

// Plugin info
#define PLUGIN_NAME			"Match Status"
#define PLUGIN_AUTHOR		"DeDstar"
#define PLUGIN_DESCRIPTION 	"Prints match status in chat (round, time limit, and score) after each round and after match ends"
#define PLUGIN_VERSION		"1.0.0"
#define PLUGIN_URL			""

// Map detection
#define PUSH 1
#define STOPWATCH 2
#define CTF 3
#define PAYLOAD 4
#define PAYLOADRACE 5
#define KOTH 6
#define ARENA 7
#define TC 8
#define ULTIDUO 9
#define BBALL 10

// Force new-style declarations (Sourcepawn 1.7 and newer)
#pragma newdecls required

bool teamReadyState[2];
bool isLive = false; // Check if game is live

char c_Minutes[5]; 				// Minutes for !status and timer at the start of each round
char c_Seconds[5]; 				// Seconds for !status and timer at the start of each round
char c_redName[36] = "RED"; 	// RED team name
char c_bluName[36] = "BLU"; 	// BLU team name
char c_mapName[50];				// Stores the current mapname

int timeLeft = 0; // Timeleft detect
int roundsPlayed = 0; // Rounds counter
int roundCounter = 0; // Count the number of rounds in Attack/Defend stype gameplay
int redScore = 0; // Score of RED
int bluScore = 0; // Score of BLU
int mapType; // Map type

public Plugin myinfo = {
	name		= PLUGIN_NAME,
	author		= PLUGIN_AUTHOR,
	description	= PLUGIN_DESCRIPTION,
	version		= PLUGIN_VERSION,
	url			= PLUGIN_URL
};

public void OnPluginStart() {
	RegConsoleCmd("sm_status", CommandStatus, "Retrieves overall server status");

	// Hook into mp_tournament_restart (for cfg execs)
	RegServerCmd("mp_tournament_restart", Event_TournamentRestart);
	
	// Hook tournament pre-game state
	HookEvent("tournament_stateupdate", Event_TournamentStateupdate);
	
	// Win conditions met (maxrounds, timelimit)
	HookEvent("teamplay_game_over", Event_GameOver);
	
	// Win conditions met (windifference)
	HookEvent("tf_game_over", Event_GameOver);
	
	// Scoreboard panel is displayed, track scores
	HookEvent("teamplay_win_panel", Event_GameWinPanel);
	
	// Start of each round
	HookEvent("teamplay_round_start", Event_RoundStart);
	
	// When a flag is captured, flag capture score tracking for bball or ctf maps
	HookEvent("ctf_flag_captured", Event_FlagCaptured);
}

public void OnMapStart() {
	setNotLive();
	DetectMap();
}

/* !status */
public Action CommandStatus(int client, int args) {
	GameStatusText(client);
}

/* client join game server status text timer callback */
public Action ShowStatusText(Handle timer, any client) {
	GameStatusText(client);
}

/* when client joins the server */
public void OnClientPutInServer(int client) {
	// create timer since doing CPrintToChat directly here doesn't work
	CreateTimer(0.3, ShowStatusText, client);
}


public void Event_TournamentStateupdate(Handle event, const char[] name, bool dontBroadcast)
{
    // significantly more robust way of getting team ready status
    // the != 0 converts the result to a bool
    teamReadyState[0] = GameRules_GetProp("m_bTeamReady", 1, 2) != 0;
    teamReadyState[1] = GameRules_GetProp("m_bTeamReady", 1, 3) != 0;

    // If both teams are ready, set to live.
    if (teamReadyState[0] && teamReadyState[1]) {
        isLive = true;
    }
	// One or more of the teams isn't ready, don't set to live.
    else {
        isLive = false;
    }
}

/* called when game ends */
public void Event_GameOver(Event event, const char[] name, bool dontBroadcast) {
	// bball game mode
	if (mapType == BBALL) {
		// timer to prevent text from getting buried by other lines in chat
		CreateTimer(0.3, GameOverBBall);
	} else {
		// timer to prevent text from getting buried by other lines in chat
		CreateTimer(0.3, GameOverMatch);
	}
}

public Action GameOverMatch(Handle timer) {
	if (bluScore == redScore)
		CPrintToChatAll("{green}[SM] {default}Match has ended! Scores are tied {olive}%i{default}:{olive}%i!", bluScore, redScore);
	else if (bluScore > redScore)
		CPrintToChatAll("{green}[SM] {default}Match has ended! %s wins {olive}%i{default}:{olive}%i!", c_bluName, bluScore, redScore);
	else if (bluScore < redScore)
		CPrintToChatAll("{green}[SM] {default}Match has ended! %s wins {olive}%i{default}:{olive}%i!", c_redName, redScore, bluScore);
	setNotLive();
}

/* show game-over text */
public Action GameOverBBall(Handle timer) {
	// timer to prevent text from getting buried by other lines in chat
	if (bluScore > redScore)
		CPrintToChatAll("{green}[SM] {default}Match over! %s wins {olive}%i{default}:{olive}%i!", c_bluName, bluScore, redScore);
	else if (bluScore < redScore)
		CPrintToChatAll("{green}[SM] {default}Match over! %s wins {olive}%i{default}:{olive}%i!", c_redName, redScore, bluScore);

	// fix logstf plugin not stopping
	ServerCommand("mp_tournament_restart");
	setNotLive();
}

/* mp_tournament_restart hook (server reset when a cfg is executed) */
public Action Event_TournamentRestart(int args) {
	// timer to prevent text from getting buried by other lines in chat
	CreateTimer(0.3, ResetText);
}

public Action ResetText(Handle timer) {
	CPrintToChatAll("{green}[SM] {default}Match is being reset.");
}

/* called at the start of each round */
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	if (isLive) {
		roundsPlayed++;
		if (roundsPlayed == 1)
			CPrintToChatAll("{green}[SM] {default}Match is LIVE! glhf!");
		else if (roundsPlayed > 1)
			printScores(0);
	}
}

/* called when a flag is captured in CTF and BBALL gamemodes */
public void Event_FlagCaptured(Event event, const char[] name, bool dontBroadcast) {
	switch (mapType) {
		case CTF, BBALL: {
			int Team = GetEventInt(event, "capping_team");
			if (Team == RED)
				redScore++;
			else if (Team == BLU)
				bluScore++;
		}
	}
}

/* called when a a round is won */
public void Event_GameWinPanel(Event event, const char[] name, bool dontBroadcast) {
	if (isLive) {
		switch (mapType) {
			case STOPWATCH, PAYLOAD: {
				bool g_RoundComplete = GetEventBool(event, "round_complete");
			
				if (g_RoundComplete) {
					roundCounter++;
					if (roundCounter >= 2) {
						int Team = GetEventInt(event, "winning_team");
					
						if (Team == RED)
							redScore++;
						else if (Team == BLU)
							bluScore++;
					}
				}
			} case TC: {
				int g_RoundComplete = GetEventInt(event, "round_complete");
			
				if (g_RoundComplete == 1) {
					int Team = GetEventInt(event, "winning_team");
				
					if (Team == RED)
						redScore++;
					else if (Team == BLU)
						bluScore++;
				}
			} default: {
				redScore = GetEventInt(event, "red_score");
				bluScore = GetEventInt(event, "blue_score");
			}
		}
	}
}

void setNotLive() {
	teamReadyState[0] = false;
	teamReadyState[1] = false;
	isLive = false;
	timeLeft = 0;
	roundsPlayed = 0;
	roundCounter = 0;
	redScore = 0;
	bluScore = 0;
}

/*  prints score status */
void printScores(int client) {
	// is actual client
	if (IsValidClient(client)) {
		if (bluScore == redScore)
			CPrintToChat(client, "{green}[SM] {default}Scores are tied {olive}%i{default}:{olive}%i", bluScore, redScore);
		else if (bluScore > redScore)
			CPrintToChat(client, "{green}[SM] {default}{blue}%s {default}is leading {olive}%i{default}:{olive}%i", c_bluName, bluScore, redScore);
		else if (bluScore < redScore)
			CPrintToChat(client, "{green}[SM] {default}{red}%s {default}is leading {olive}%i{default}:{olive}%i", c_redName, redScore, bluScore);
		
		GetMapTimeLeft(timeLeft);
		//Set time. If time is less than 10 add a 0.
		FormatEx(c_Minutes, sizeof(c_Minutes), "%s%i", ((timeLeft / 60) < 10)? "0" : "", timeLeft / 60);
		FormatEx(c_Seconds, sizeof(c_Seconds), "%s%i", ((timeLeft % 60) < 10)? "0" : "", timeLeft % 60);

		if (timeLeft >= 0)
			CPrintToChat(client, "{green}[SM] {default}About {mediumspringgreen}%s:%s {default}remaining in this match", c_Minutes, c_Seconds);
		else
			CPrintToChat(client, "{green}[SM] {default}This match has no time limit", c_Minutes, c_Seconds);
	}
	// not client, print to all
	else if (client == 0) {
		if (bluScore == redScore) {
			CPrintToChatAll("{green}[SM] {default}Scores are tied {olive}%i{default}:{olive}%i", bluScore, redScore);
		} else if (bluScore > redScore) {
			CPrintToChatAll("{green}[SM] {default}{blue}%s {default}is leading {olive}%i{default}:{olive}%i", c_bluName, bluScore, redScore);
		} else if (bluScore < redScore) {
			CPrintToChatAll("{green}[SM] {default}{red}%s {default}is leading {olive}%i{default}:{olive}%i", c_redName, redScore, bluScore);
		}
		
		GetMapTimeLeft(timeLeft);
		//Set time. If time is less than 10 add a 0.
		FormatEx(c_Minutes, sizeof(c_Minutes), "%s%i", ((timeLeft / 60) < 10)? "0" : "", timeLeft / 60);
		FormatEx(c_Seconds, sizeof(c_Seconds), "%s%i", ((timeLeft % 60) < 10)? "0" : "", timeLeft % 60);
		
		if (timeLeft >= 0)
			CPrintToChatAll("{green}[SM] {default}About {mediumspringgreen}%s:%s {default}remaining in this match, round: %i", c_Minutes, c_Seconds, roundsPlayed);
		else
			CPrintToChatAll("{green}[SM] {default}This match has no time limit, current round: %i", c_Minutes, c_Seconds, roundsPlayed);
	}
}

void GameStatusText(int client) {
	if (!isLive) {
		CPrintToChat(client, "{green}[SM] {default}Currently in warm-up period");
	} else {
		CPrintToChat(client, "{green}[SM] {default}Match is currently live");
		printScores(client);
	}
}

/* This routine detects the map type, original function written by Berni */
void DetectMap() {
	int iEnt = -1;
	bool bAttackPoint = false;

	GetCurrentMap(c_mapName, sizeof(c_mapName));
	if (strncmp(c_mapName, "cp_", 3, false) == 0) {
		int Team;
		while ((iEnt = FindEntityByClassname(iEnt, "team_control_point")) != -1) {
			Team = GetEntProp(iEnt, Prop_Send, "m_iTeamNum");
			/**
			* If there is a blu CP or a neutral CP, then it's not an attack/defend map
			*
			**/
			if (Team != RED) {
				mapType = STOPWATCH;
				break;
			}
		}
		if (!bAttackPoint)
			mapType = PUSH;
	}
	else if (strncmp(c_mapName, "ultiduo_", 8, false) == 0 || strncmp(c_mapName, "koth_ultiduo_", 13, false) == 0 || StrContains(c_mapName, "ultiduo", false) == 0)
		mapType = ULTIDUO;
	else if (strncmp(c_mapName, "ctf_ballin_", 11, false) == 0 || strncmp(c_mapName, "ctf_bball_", 10, false) == 0 || StrContains(c_mapName, "bball", false) == 0)
		mapType = BBALL;
	else if (strncmp(c_mapName, "ctf_", 3, false) == 0)
		mapType = CTF;
	else if (strncmp(c_mapName, "pl_", 3, false) == 0)
		mapType = PAYLOAD;
	else if (strncmp(c_mapName, "plr_", 4, false) == 0)
		mapType = PAYLOADRACE;
	else if (strncmp(c_mapName, "arena_", 6, false) == 0)
		mapType = ARENA;
	else if (strncmp(c_mapName, "tc_", 3, false) == 0)
		mapType = TC;
	else // unknown map type, automatically default to push
		mapType = PUSH;
}

/* Prevents invalid client error in sourcemod error logs */
bool IsValidClient(int client) {
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client))
		return false;
	return true;
}