#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <morecolors>

#define PLUGIN_VERSION		"1.7"

public Plugin myinfo = {
	name		= "[NGS] Kartify",
	author		= "Dr. McKay / TheXeon",
	description	= "Put players into karts!",
	version		= PLUGIN_VERSION,
	url			= "http://www.doctormckay.com"
}

Handle g_cvarSpawnKart;
Handle g_cvarStartPercentage;
Handle g_cvarForcedPercentage;
Handle g_cvarAllowSuicide;

bool g_KartSpawn[MAXPLAYERS + 1];

#define UPDATE_FILE		"kartify.txt"
#define CONVAR_PREFIX	"kartify"

#include "mckayupdater.sp"

public void OnPluginStart() {
	g_cvarSpawnKart = CreateConVar("kartify_spawn", "0", "0 = do nothing, 1 = put all players into karts when they spawn, 2 = put players into karts when they spawn only if sm_kartify was used on them", _, true, 0.0, true, 2.0);
	g_cvarStartPercentage = CreateConVar("kartify_start_percentage", "0", "Starting percentage, as an integer, of damage for kartified players", _, true, 0.0);
	g_cvarForcedPercentage = CreateConVar("kartify_forced_percentage", "-1", "If 0 or greater, karts will not take damage and will instead have this percent of damage all the time (as an integer)", _, true, -1.0);
	g_cvarAllowSuicide = CreateConVar("kartify_allow_suicide", "1", "Allow players to suicide while in a kart", _, true, 0.0, true, 1.0);
	
	RegAdminCmd("sm_kartify", Command_Kartify, ADMFLAG_SLAY, "Put players into karts!");
	RegAdminCmd("sm_kart", Command_Kartify, ADMFLAG_SLAY, "Put players into karts!");
	RegAdminCmd("sm_unkartify", Command_Unkartify, ADMFLAG_SLAY, "Remove players from karts");
	RegAdminCmd("sm_unkart", Command_Unkartify, ADMFLAG_SLAY, "Remove players from karts");
	RegAdminCmd("sm_kartifyme", Command_KartifyMe, ADMFLAG_SLAY, "Puts you into a kart!");
	RegAdminCmd("sm_kartme", Command_KartifyMe, ADMFLAG_SLAY, "Puts you into a kart!");
	RegAdminCmd("sm_unkartifyme", Command_UnkartifyMe, ADMFLAG_SLAY, "Removes you from a kart");
	RegAdminCmd("sm_unkartme", Command_UnkartifyMe, ADMFLAG_SLAY, "Removes you from a kart");
	
	LoadTranslations("common.phrases");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_team", Event_PlayerTeam);
	
	AddCommandListener(Command_Kill, "kill");
	AddCommandListener(Command_Kill, "explode");
}

public Action Command_Kill(int client, const char[] command, int argc) {
	if(GetConVarBool(g_cvarAllowSuicide)) {
		Unkartify(client); // Won't do anything if they're not in a kart
	}
}

public void OnMapStart() {
	PrecacheModel("models/player/items/taunts/bumpercar/parts/bumpercar.mdl");
	PrecacheModel("models/player/items/taunts/bumpercar/parts/bumpercar_nolights.mdl");
	
	PrecacheSound(")weapons/bumper_car_accelerate.wav");
	PrecacheSound(")weapons/bumper_car_decelerate.wav");
	PrecacheSound(")weapons/bumper_car_decelerate_quick.wav");
	PrecacheSound(")weapons/bumper_car_go_loop.wav");
	PrecacheSound(")weapons/bumper_car_hit_ball.wav");
	PrecacheSound(")weapons/bumper_car_hit_ghost.wav");
	PrecacheSound(")weapons/bumper_car_hit_hard.wav");
	PrecacheSound(")weapons/bumper_car_hit_into_air.wav");
	PrecacheSound(")weapons/bumper_car_jump.wav");
	PrecacheSound(")weapons/bumper_car_jump_land.wav");
	PrecacheSound(")weapons/bumper_car_screech.wav");
	PrecacheSound(")weapons/bumper_car_spawn.wav");
	PrecacheSound(")weapons/bumper_car_spawn_from_lava.wav");
	PrecacheSound(")weapons/bumper_car_speed_boost_start.wav");
	PrecacheSound(")weapons/bumper_car_speed_boost_stop.wav");
	
	char name[64];
	for(int i = 1; i <= 8; i++) {
		FormatEx(name, sizeof(name), "weapons/bumper_car_hit%d.wav", i);
		PrecacheSound(name);
	}
}

public void OnClientConnected(int client) {
	g_KartSpawn[client] = false;
}

public Action Command_Kartify(int client, int args) {
	if(args == 0) {
		CReplyToCommand(client, "{GREEN}[SM]{DEFAULT} Usage: sm_kartify <name|#userid>");
		return Plugin_Handled;
	}
	
	char argString[MAX_NAME_LENGTH];
	GetCmdArgString(argString, sizeof(argString));
	StripQuotes(argString);
	TrimString(argString);
	
	int targets[MAXPLAYERS]; 
	char target_name[MAX_NAME_LENGTH];
	bool tn_is_ml;
	
	int result = ProcessTargetString(argString, client, targets, MaxClients, COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml);
	if(result <= 0) {
		ReplyToTargetError(client, result);
		return Plugin_Handled;
	}
	
	if(result == 1 && TF2_IsPlayerInCondition(targets[0], view_as<TFCond>(82))) {
		// Only one player chosen and they're in a kart
		CShowActivity2(client, "{GREEN}[SM]{DEFAULT} ", "Unkartified {LIGHTGREEN}%s{DEFAULT}!", target_name);
		LogAction(client, targets[0], "\"%L\" unkartified \"%L\"", client, targets[0]);
		g_KartSpawn[targets[0]] = false;
		Unkartify(targets[0]);
		return Plugin_Handled;
	}
	
	CShowActivity2(client, "{GREEN}[SM]{DEFAULT} ", "Kartified {LIGHTGREEN}%s{DEFAULT}!", target_name);
	for(int i = 0; i < result; i++) {
		LogAction(client, targets[i], "\"%L\" kartified \"%L\"", client, targets[i]);
		g_KartSpawn[targets[i]] = true;
		Kartify(targets[i]);
	}
	
	return Plugin_Handled;
}

public Action Command_Unkartify(int client, int args) {
	if(args == 0) {
		CReplyToCommand(client, "{GREEN}[SM]{DEFAULT} Usage: sm_unkartify <name|#userid>");
		return Plugin_Handled;
	}
	
	char argString[MAX_NAME_LENGTH];
	GetCmdArgString(argString, sizeof(argString));
	StripQuotes(argString);
	TrimString(argString);
	
	int targets[MAXPLAYERS]; 
	char target_name[MAX_NAME_LENGTH];
	bool tn_is_ml;
	int result = ProcessTargetString(argString, client, targets, MaxClients, COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml);
	if(result <= 0) {
		ReplyToTargetError(client, result);
		return Plugin_Handled;
	}
	
	CShowActivity2(client, "{GREEN}[SM]{DEFAULT} ", "Unkartified {LIGHTGREEN}%s{DEFAULT}!", target_name);
	for(int i = 0; i < result; i++) {
		LogAction(client, targets[i], "\"%L\" unkartified \"%L\"", client, targets[i]);
		g_KartSpawn[targets[i]] = false;
		Unkartify(targets[i]);
	}
	
	return Plugin_Handled;
}

public Action Command_KartifyMe(int client, int args) {
	if(TF2_IsPlayerInCondition(client, view_as<TFCond>(82))) {
		Command_UnkartifyMe(client, 0);
		return Plugin_Handled;
	}
	
	CShowActivity2(client, "{GREEN}[SM]{LIGHTGREEN} ", "{DEFAULT}Put self into a kart.");
	LogAction(client, client, "\"%L\" put themselves into a kart", client);
	g_KartSpawn[client] = true;
	Kartify(client);
	return Plugin_Handled;
}

public Action Command_UnkartifyMe(int client, int args) {
	CShowActivity2(client, "{GREEN}[SM]{LIGHTGREEN} ", "{DEFAULT}Removed self from a kart.");
	LogAction(client, client, "\"%L\" removed themselves from a kart", client);
	g_KartSpawn[client] = false;
	Unkartify(client);
	return Plugin_Handled;
}

public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast) {
	int mode = GetConVarInt(g_cvarSpawnKart);
	if(mode == 0) {
		return;
	}
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(mode == 1 || (mode == 2 && g_KartSpawn[client])) {
		Kartify(client);
	}
}

public void Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(TF2_IsPlayerInCondition(client, view_as<TFCond>(82))) {
		// Kill them otherwise they'll just spawn as the other team where they're standing
		Unkartify(client);
		ForcePlayerSuicide(client);
	}
}

void Kartify(int client) {
	TF2_AddCondition(client, view_as<TFCond>(82), TFCondDuration_Infinite);
	SetEntProp(client, Prop_Send, "m_iKartHealth", GetConVarInt(g_cvarStartPercentage));
}

void Unkartify(int client) {
	TF2_RemoveCondition(client, view_as<TFCond>(82));
}

public void OnGameFrame() {
	int forcedPct = GetConVarInt(g_cvarForcedPercentage);
	if(forcedPct >= 0) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				SetEntProp(i, Prop_Send, "m_iKartHealth", forcedPct);
			}
		}
	}
}