-- Gamble: lokale WoW-Forever-Instanzdaten.
-- Neue Bosse und Drops nur hier ergänzen; die Spiellogik bleibt in Gamble.lua.
GambleData = GambleData or {}
GambleData.updated = "2026-09-26 / Forever beta 1.60.1.70009"
GambleData.instanceAliases = {
    ["Stormwind Stockade"] = "The Stockade",
    ["Stormwind Stockades"] = "The Stockade",
    ["The Stockades"] = "The Stockade",
    ["Stockade"] = "The Stockade",
    ["The Hall of Thanes"] = "Hall of Thanes",
    ["Excavation Site"] = "Excavation Site: Wetlands",
    ["Dalaran"] = "City of Dalaran",
    ["Drowned City"] = "The Drowned City",
    ["The Temple of Atal'Hakkar"] = "Sunken Temple",
    ["Temple of Atal'Hakkar"] = "Sunken Temple",
    ["Stratholme Main Gate"] = "Stratholme",
    ["Stratholme Service Gate"] = "Stratholme",
    ["Scarlet Monastery"] = "Scarlet Monastery Cathedral",
    ["The Ruins of Ahn'Qiraj"] = "Ruins of Ahn'Qiraj",
    ["The Temple of Ahn'Qiraj"] = "Temple of Ahn'Qiraj",
}
GambleData.instances = GambleClassicData or {}
-- Entrance zones (localized clients use the same map IDs). Unknown zones retain the full list.
GambleData.instanceZones = {
    [52]={"The Deadmines"}, [37]={"The Stockade"}, [84]={"The Stockade"},
    [27]={"Gnomeregan"}, [1]={"Ragefire Chasm"}, [85]={"Ragefire Chasm"},
    [10]={"Wailing Caverns","Razorfen Kraul","Razorfen Downs"}, [199]={"Razorfen Kraul","Razorfen Downs"},
    [21]={"Shadowfang Keep"}, [18]={"Scarlet Monastery Cathedral","Scarlet Monastery Library","Scarlet Monastery Armory","Scarlet Monastery Graveyard"},
    [15]={"Uldaman"}, [51]={"Sunken Temple"}, [71]={"Zul'Farrak"},
    [69]={"Dire Maul East","Dire Maul West","Dire Maul North"}, [22]={"Scholomance"}, [23]={"Stratholme"},
    [32]={"Blackrock Depths","Lower Blackrock Spire","Upper Blackrock Spire","Molten Core","Blackwing Lair"},
    [28]={"Blackrock Depths","Lower Blackrock Spire","Upper Blackrock Spire","Molten Core","Blackwing Lair"},
    [50]={"Zul'Gurub"}, [70]={"Onyxia's Lair"}, [81]={"Ruins of Ahn'Qiraj","Temple of Ahn'Qiraj"},
    [40]={"Excavation Site: Wetlands"},
}
-- Classic/Forever area-map IDs differ from Retail; names also cover custom maps.
GambleData.instanceZones[1413]=GambleData.instanceZones[10]
GambleData.instanceZoneNames={
    ["The Barrens"]=GambleData.instanceZones[10], ["Barrens"]=GambleData.instanceZones[10],
    ["Brachland"]=GambleData.instanceZones[10], ["Das Brachland"]=GambleData.instanceZones[10],
    ["Northern Barrens"]=GambleData.instanceZones[10], ["Nördliches Brachland"]=GambleData.instanceZones[10],
    ["Southern Barrens"]=GambleData.instanceZones[199], ["Südliches Brachland"]=GambleData.instanceZones[199],
    ["Westfall"]=GambleData.instanceZones[52], ["Durotar"]=GambleData.instanceZones[1],
    ["Orgrimmar"]=GambleData.instanceZones[85], ["Stormwind City"]=GambleData.instanceZones[84],
    ["Sturmwind"]=GambleData.instanceZones[84], ["Silverpine Forest"]=GambleData.instanceZones[21],
    ["Silberwald"]=GambleData.instanceZones[21], ["Tirisfal Glades"]=GambleData.instanceZones[18],
    ["Tirisfal"]=GambleData.instanceZones[18], ["Wetlands"]=GambleData.instanceZones[40],
    ["Sumpfland"]=GambleData.instanceZones[40],
}
function GambleData.GetZoneInstances()
    for _,getter in pairs({GetRealZoneText,GetZoneText}) do
        local ok,name=pcall(getter)
        if ok and type(name)=="string" and (not canaccessvalue or canaccessvalue(name)) and (not issecretvalue or not issecretvalue(name)) then
            local entries=GambleData.instanceZoneNames[name]
            if entries then return entries end
        end
    end
    local mapID=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for i=1,8 do
        if not mapID then break end
        if GambleData.instanceZones[mapID] then return GambleData.instanceZones[mapID] end
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID=info and info.parentMapID
    end
    return {}
end
local foreverInstances = {
    ["The Stockade"] = {
        { name="Kam Deepfury", loot={{id=2280,name="Kam's Walking Stick"},{id=273808,name="Bridgebreaker Bindings"}} },
        { name="Bruegal Ironknuckle", loot={{id=3228,name="Jimmied Handcuffs"},{id=2941,name="Prison Shank"},{id=2942,name="Iron Knuckles"}} },
        { name="Targorr the Dread", loot={{id=273804,name="Executioner Mantle"},{id=273805,name="Blackrock Harness"},{id=273806,name="Dark Horde Band"},{id=273820,name="Nightskulker Ring"}} },
        { name="Hamhock", loot={{id=273809,name="Hamhock's Cleaver"},{id=273810,name="Ogre Grips"}} },
        { name="Bazil Thredd", loot={{id=273824,name="Defias Jailbreakers"},{id=273825,name="Red Wool Cloak"},{id=273827,name="Debt Collector"},{id=273829,name="Concealed Hand Crossbow"}} },
    },
    ["Hall of Thanes"] = {
        { name="Faldrim Anvilmar", loot={{id=270227,name="Ephemeral Choker"},{id=271096,name="Aetherwisp Bracers"},{id=271097,name="Spiritwraith Drape"}} },
        { name="Magmatus", loot={{id=270230,name="Kindlegem Girdle"},{id=270231,name="Flamefist Grips"},{id=271095,name="Fang of Magmatus"}} },
        { name="Plunder", loot={{id=270228,name="Golemheart Stave"},{id=270229,name="Treads of the Protector Golem"},{id=271098,name="Golemguard Chest"}} },
        { name="Durgen Dirgehammer", loot={{id=270256,name="Durgen's Crescent Axe"},{id=270260,name="Direhammer Leggings"},{id=270261,name="Robes of the Disgraced Thane"}} },
    },
    ["Ruins of Lordaeron"] = {
        { name="Witherfang", loot={{id=271201,name="Atrophic Girdle"},{id=271202,name="Witherbite Bracers"},{id=271203,name="Segmented Spider Leg"}} },
        { name="The Abandoned", loot={{id=271207,name="Rotmender's Leggings"},{id=271208,name="Grip of Fear"},{id=271216,name="Scepter of the Abandoned"}} },
        { name="The Butcher", aliases={"The Baron"}, loot={{id=271204,name="Meathook Slicer"},{id=271205,name="Abomination Bones"},{id=271206,name="Leftover Abomination Skin"}} },
        { name="Rath'mael", loot={{id=271213,name="Mirror of Rath'mael"},{id=271214,name="Rotmender's Treads"},{id=271215,name="Coldspire Staff"}} },
        { name="Lordaeron Captain", loot={{id=6641,name="Haunting Blade"},{id=6642,name="Phantom Armor"}} },
        { name="Viktor the Vile", loot={{id=271211,name="Vilewalkers"},{id=271212,name="Bloodied Chestwraps"},{id=271218,name="Vileblood Scimitar"}} },
        { name="Bjork", loot={{id=271209,name="Bonerust Leggings"},{id=271210,name="Tuskwrap Belt"},{id=271217,name="Corpse Chopper"}} },
    },
    ["Excavation Site: Wetlands"] = {
        {name="Saltspine",loot={}},{name="Shadetooth",loot={}},{name="Highland Horror",loot={}},{name="Relic Guardian",loot={}},
    },
    ["City of Dalaran"] = {
        {name="Arcane Anomaly",loot={}},{name="Fel Ancient",loot={}},{name="Mana Devourer",loot={}},{name="Mana Elemental",loot={}},{name="Unstable Sentinel",loot={}},{name="Shade of the Archmage",loot={}},{name="Lyn the Ignored",loot={}},{name="Atrexis the Grave Knight",loot={}},{name="Mana Wraith",loot={}},
    },
    -- Für diese angekündigten Instanzen sind derzeit noch keine verlässlichen Boss-/Lootdaten veröffentlicht.
    ["The Drowned City"] = {}, ["Krol'dok Stronghold"] = {}, ["Alcaz Prison"] = {},
    ["Blackmaw Hold"] = {}, ["Shaper's Terrace"] = {},
}
for instanceName, bosses in pairs(foreverInstances) do GambleData.instances[instanceName] = bosses end

-- AtlasLootClassic specialType="rare"; shared by fallback and journal bosses.
GambleData.rareBosses = {
    ["Deviate Faerie Dragon"]=true, ["Miner Johnson"]=true,
    ["Deathsworn Captain"]=true, ["Bruegal Ironknuckle"]=true,
    ["Dark Iron Ambassador"]=true, ["Blind Hunter"]=true,
    ["Earthcaller Halmgar"]=true, ["Azshir the Sleepless"]=true,
    ["Fallen Champion"]=true, ["Ironspine"]=true, ["Ragglesnout"]=true,
    ["Sandarr Dunereaver"]=true, ["Dustwraith"]=true, ["Zerillis"]=true,
    ["Meshlok the Harvester"]=true, ["Pyromancer Loregrain"]=true,
    ["Panzor the Invincible"]=true, ["Burning Felguard"]=true,
    ["Spirestone Butcher"]=true, ["Spirestone Battle Lord"]=true,
    ["Spirestone Lord Magus"]=true, ["Bannok Grimaxe"]=true,
    ["Crystal Fang"]=true, ["Ghok Bashguud"]=true, ["Jed Runewatcher"]=true,
    ["Tsu'zee"]=true, ["Skul"]=true, ["Hearthsinger Forresten"]=true,
    ["Stonespine"]=true,
}
function GambleData.IsRareBoss(boss)
    if boss and boss.rare~=nil then return boss.rare end
    return boss and (boss.rare or GambleData.rareBosses[boss.name]) or false
end
function GambleData.SeriesBossCounts(boss, result)
    return not GambleData.IsRareBoss(boss) or (result and result.name ~= "Not scored" and not result.skipped) or false
end

-- The shredder and Sneed are separate, required encounters, in fight order.
local deadmines = GambleData.instances["The Deadmines"] or {}
local sneedIndex, shredderIndex
for i, boss in ipairs(deadmines) do
    if boss.name == "Sneed" then sneedIndex = i end
    if boss.name == "Sneed's Shredder" then shredderIndex = i end
end
if sneedIndex and shredderIndex and shredderIndex > sneedIndex then
    table.insert(deadmines, sneedIndex, table.remove(deadmines, shredderIndex))
end

-- Audited against installed ForeverDungeonJournal Data/Dungeons.lua, 2026-10-04.
-- Only encounter entries: journal Trash Drops and AtlasLoot quest-item rows are excluded.
local journalBosses = {
    ["Blackfathom Deeps"] = {
        {name="Ghamoo-ra", rare=false, npcID=4887, loot={{id=6907,name="Tortoise Armor"},{id=6908,name="Ghamoo-ra's Bind"},{id=273839,name="Spiked Shell Band"},{id=251382,name="Plans: Protector's Silvered Chain Helm"},{id=252801,name="Pattern: Totemic Leather Hood"},{id=253940,name="Pattern: Filigreed Silky Leggings"},{id=253942,name="Pattern: Filigreed Flame Leggings"},}},
        {name="Lady Sarevess", rare=false, npcID=4831, loot={{id=888,name="Naga Battle Gloves"},{id=3078,name="Naga Heartpiercer"},{id=11121,name="Darkwater Talwar"},{id=252798,name="Pattern: Brawler's Leather Hood"},{id=251382,name="Plans: Protector's Silvered Chain Helm"},{id=251383,name="Plans: Acolyte's Silvered Chain Helm"},{id=253944,name="Pattern: Filigreed Shadow Leggings"},}},
        {name="Gelihast", rare=false, npcID=6243, loot={{id=6906,name="Algae Fists"},{id=6905,name="Reef Axe"},{id=1470,name="Murloc Skin Bag"},{id=273840,name="Cursed Murloc Eye"},{id=251375,name="Plans: Veteran's Silvered Chain Leggings"},{id=251377,name="Plans: Protector's Silvered Chain Leggings"},{id=252820,name="Pattern: Brawler's Leather Legguards"},{id=252821,name="Pattern: Trapper's Leather Legguards"},{id=252825,name="Pattern: Wisdom's Leather Leggings"},{id=253978,name="Pattern: Filigreed Silky Circlet"},{id=253980,name="Pattern: Filigreed Flame Circlet"},{id=273141,name="Blueprint: Fishing Rack"},}},
        {name="Lorgus Jett", rare=false, npcID=12902, loot={{id=273843,name="Fallenroot Longbow"},{id=273841,name="Twilight Maul"},{id=273842,name="Treacherous Treads"},{id=253978,name="Pattern: Filigreed Silky Circlet"},{id=253982,name="Pattern: Filigreed Shadow Circlet"},}},
        {name="Baron Aquanis", rare=false, npcID=12876, loot={{id=16782,name="Strange Water Globe"},{id=252822,name="Pattern: Defender's Leather Kilt"},{id=253980,name="Pattern: Filigreed Flame Circlet"},}},
        {name="Old Serra'kis", rare=false, npcID=4830, loot={{id=6901,name="Glowing Thresher Cape"},{id=6904,name="Bite of Serra'kis"},{id=6902,name="Bands of Serra'kis"},{id=251375,name="Plans: Veteran's Silvered Chain Leggings"},{id=252825,name="Pattern: Wisdom's Leather Leggings"},{id=253978,name="Pattern: Filigreed Silky Circlet"},{id=253982,name="Pattern: Filigreed Shadow Circlet"},}},
        {name="Twilight Lord Kelris", rare=false, npcID=4832, loot={{id=1155,name="Rod of the Sleepwalker"},{id=6903,name="Gaze Dreamer Pants"},{id=273846,name="Twilight Lord Girdle"},{id=252820,name="Pattern: Brawler's Leather Legguards"},{id=252821,name="Pattern: Trapper's Leather Legguards"},{id=252822,name="Pattern: Defender's Leather Kilt"},{id=252823,name="Pattern: Totemic Leather Leggings"},{id=252825,name="Pattern: Wisdom's Leather Leggings"},{id=253982,name="Pattern: Filigreed Shadow Circlet"},}},
        {name="Aku'mai", rare=false, npcID=4829, loot={{id=6911,name="Moss Cinch"},{id=6910,name="Leech Pants"},{id=6909,name="Strike of the Hydra"},{id=251376,name="Plans: Guard's Silvered Chain Leggings"},{id=251377,name="Plans: Protector's Silvered Chain Leggings"},{id=251378,name="Plans: Acolyte's Silvered Chain Leggings"},{id=252821,name="Pattern: Trapper's Leather Legguards"},{id=252824,name="Pattern: Stormrider's Leather Kilt"},{id=253980,name="Pattern: Filigreed Flame Circlet"},{id=253984,name="Pattern: Filigreed Pearly Circlet"},}},
    },
    ["City of Dalaran"] = {
        {name="Atrexis the Grave Knight", rare=false, npcID=247126, loot={}},
        {name="Arcane Anomaly", rare=false, npcID=245999, loot={}},
        {name="Fel Ancient", rare=false, npcID=246003, loot={}},
        {name="Unstable Sentinel", rare=false, npcID=246017, loot={{id=273046,name="Guardian's Dualblade"},}},
        {name="Mana Wraith", rare=false, npcID=246931, loot={}},
        {name="Mana Devourer", rare=false, npcID=246008, loot={}},
        {name="Mana Elemental", rare=false, loot={}},
        {name="Lyn the Ignored", rare=true, npcID=247032, loot={}},
        {name="Shade of the Archmage", rare=false, npcID=246020, loot={{id=273052,name="Ponderous Orb"},}},
    },
    ["Excavation Site: Wetlands"] = {
        {name="Saltspine", rare=false, npcID=260322, loot={{id=273024,name="Glinteye Slippers"},{id=273022,name="Supple Bellyskin Leggings"},{id=273023,name="Saltscale Girdle"},}},
        {name="Shadetooth", rare=false, npcID=260325, loot={{id=273025,name="Raptorclaw Greaves"},{id=273027,name="Raptor's Gaze"},{id=273106,name="Blueprint: Greenhouse"},}},
        {name="Relic Guardian", rare=false, npcID=260326, loot={{id=273028,name="Reliquary Mantle"},{id=273029,name="Golemsight Long Gun"},{id=273030,name="Ring of Power Regulation"},{id=270866,name="Titan Relic"},{id=273097,name="Blueprint: Rock Garden"},}},
    },
    ["Gnomeregan"] = {
        {name="Grubbis", rare=false, npcID=7361, loot={{id=9445,name="Grubbis Paws"},}},
        {name="Viscous Fallout", rare=false, npcID=7079, loot={{id=9452,name="Hydrocane"},{id=9453,name="Toxic Revenger"},{id=9454,name="Acidic Walkers"},}},
        {name="Electrocutioner 6000", rare=false, npcID=6235, loot={{id=9446,name="Electrocutioner Leg"},{id=9447,name="Electrocutioner Lagnut"},{id=9448,name="Spidertank Oilrag"},}},
        {name="Crowd Pummeler 9-60", rare=false, npcID=6229, loot={{id=9449,name="Manual Crowd Pummeler"},{id=9450,name="Gnomebot Operating Boots"},}},
        {name="Mekgineer Thermaplugg", rare=false, npcID=7800, loot={{id=9458,name="Thermaplugg's Central Core"},{id=9459,name="Thermaplugg's Left Arm"},{id=9461,name="Charged Gear"},{id=9492,name="Electromagnetic Gigaflux Reactivator"},}},
        {name="Dark Iron Ambassador", rare=true, npcID=6228, loot={{id=9455,name="Emissary Cuffs"},{id=9456,name="Glass Shooter"},{id=9457,name="Royal Diplomatic Scepter"},}},
    },
    ["Hall of Thanes"] = {
        {name="Faldrim Anvilmar", rare=false, npcID=261306, loot={{id=270227,name="Ephemeral Choker"},{id=271096,name="Aetherwisp Bracers"},{id=271097,name="Spiritwraith Drape"},}},
        {name="Magmatus", rare=false, loot={{id=270230,name="Kindlegem Girdle"},{id=270231,name="Flamefist Grips"},{id=271095,name="Fang of Magmatus"},}},
        {name="Plunder", rare=false, npcID=261311, loot={{id=270228,name="Golemheart Stave"},{id=271098,name="Golemguard Chest"},{id=270229,name="Treads of the Protector Golem"},}},
        {name="Durgen Dirgehammer", rare=false, npcID=261319, loot={{id=270256,name="Durgen's Crescent Axe"},{id=270260,name="Direhammer Leggings"},{id=270261,name="Robes of the Disgraced Thane"},{id=274286,name="Durgen Dirgehammer's Head"},}},
    },
    ["Ragefire Chasm"] = {
        {name="Oggleflint", rare=false, npcID=11517, loot={{id=272999,name="Barbaric Crossbow"},{id=272996,name="Trogg Scepter"},{id=272998,name="Bone Knuckles"},{id=252781,name="Pattern: Stormrider's Leather Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},}},
        {name="Taragaman the Hungerer", rare=false, npcID=11520, loot={{id=14149,name="Subterranean Cape"},{id=14148,name="Crystalline Cuffs"},{id=14145,name="Cursed Felblade"},{id=251361,name="Plans: Guard's Gloves"},{id=251362,name="Plans: Protector's Gloves"},{id=251363,name="Plans: Acolyte's Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},}},
        {name="Jergosh the Invoker", rare=false, npcID=11518, loot={{id=14150,name="Robe of Evocation"},{id=14147,name="Cavedweller Bracers"},{id=14151,name="Chanting Blade"},{id=251360,name="Plans: Veteran's Gloves"},{id=253906,name="Pattern: Filigreed Flame Gown"},}},
        {name="Bazzalan", rare=false, npcID=11519, loot={{id=273003,name="Searing Dagger"},{id=273007,name="Chasm Walkers"},{id=273005,name="Satyrskin Cloak"},{id=252780,name="Pattern: Totemic Leather Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},{id=253908,name="Pattern: Filigreed Shadow Gown"},{id=253910,name="Pattern: Filigreed Pearly Gown"},}},
    },
    ["Razorfen Kraul"] = {
        {name="Roogug", rare=false, npcID=6168, loot={{id=274155,name="Geomancer Headdress"},{id=274152,name="Roogug's Severed Head"},}},
        {name="Aggem Thorncurse", rare=false, npcID=4424, loot={{id=6681,name="Thornspike"},{id=274158,name="Death Prophet Spine"},{id=252820,name="Pattern: Brawler's Leather Legguards"},}},
        {name="Death Speaker Jargba", rare=false, npcID=4428, loot={{id=2816,name="Death Speaker Scepter"},{id=6685,name="Death Speaker Mantle"},{id=6682,name="Death Speaker Robes"},}},
        {name="Overlord Ramtusk", rare=false, npcID=4420, loot={{id=6687,name="Corpsemaker"},{id=6686,name="Tusken Helm"},{id=274161,name="Quillord Mail Leggings"},{id=251379,name="Plans: Crusader's Silvered Chain Leggings"},{id=252821,name="Pattern: Trapper's Leather Legguards"},}},
        {name="Agathelos the Raging", rare=false, npcID=4422, loot={{id=6691,name="Swinetusk Shank"},{id=6690,name="Ferine Leggings"},{id=274160,name="Quilrager Throwing Axe"},{id=251378,name="Plans: Acolyte's Silvered Chain Leggings"},}},
        {name="Charlga Razorflank", rare=false, npcID=4421, loot={{id=6693,name="Agamaggan's Clutch"},{id=6694,name="Heart of Agamaggan"},{id=6692,name="Pronged Reaver"},{id=273103,name="Blueprint: Arcane Salvager"},}},
        {name="Blind Hunter", rare=true, npcID=4425, loot={{id=6695,name="Stygian Bone Amulet"},{id=6697,name="Batwing Mantle"},{id=6696,name="Nightstalker Bow"},}},
        {name="Earthcaller Halmgar", rare=true, npcID=4842, loot={{id=6689,name="Wind Spirit Staff"},{id=6688,name="Whisperwind Headdress"},}},
    },
    ["Ruins of Lordaeron"] = {
        {name="The Baron", rare=false, npcID=250660, loot={{id=271204,name="Meathook Slicer"},{id=271205,name="Abomination Bones"},{id=271206,name="Leftover Abomination Skin"},}},
        {name="Witherfang", rare=false, npcID=250483, loot={{id=271201,name="Atrophic Girdle"},{id=271202,name="Witherbite Bracers"},{id=271203,name="Segmented Spider Leg"},}},
        {name="The Abandoned", rare=false, npcID=250631, loot={{id=271207,name="Rotmender's Leggings"},{id=271208,name="Grip of Fear"},{id=271216,name="Scepter of the Abandoned"},}},
        {name="Bjork", rare=false, npcID=256097, loot={{id=271209,name="Bonerust Leggings"},{id=271210,name="Tuskwrap Belt"},{id=271217,name="Corpse Chopper"},}},
        {name="Rath'mael", rare=false, npcID=250657, loot={{id=271213,name="Mirror of Rath'mael"},{id=271214,name="Rotmender's Treads"},{id=271215,name="Coldspire Staff"},{id=273085,name="Blueprint: Fermenter"},{id=273103,name="Blueprint: Arcane Salvager"},}},
        {name="Viktor the Vile", rare=false, npcID=256035, loot={{id=271211,name="Vilewalkers"},{id=271212,name="Bloodied Chestwraps"},{id=271218,name="Vileblood Scimitar"},}},
        {name="Lordaeron Captain", rare=true, loot={{id=6641,name="Haunting Blade"},{id=6642,name="Phantom Armor"},}},
    },
    ["Scarlet Monastery: Graveyard"] = {
        {name="Interrogator Vishas", rare=false, npcID=3983, loot={{id=7682,name="Torturing Poker"},{id=7683,name="Bloody Brass Knuckles"},{id=274290,name="Painwalker Buckler"},{id=252513,name="Trapper's Leather Helm"},}},
        {name="Azshir the Sleepless", rare=true, npcID=6490, loot={{id=7709,name="Blighted Leggings"},{id=7708,name="Necrotic Wand"},{id=7731,name="Ghostshard Talisman"},}},
        {name="Fallen Champion", rare=true, npcID=6488, loot={{id=7691,name="Embalmed Shroud"},{id=7690,name="Ebon Vise"},{id=7689,name="Morbid Dawn"},{id=252513,name="Trapper's Leather Helm"},}},
        {name="Ironspine", rare=true, npcID=6489, loot={{id=7688,name="Ironspine's Ribcage"},{id=7687,name="Ironspine's Fist"},{id=7686,name="Ironspine's Eye"},}},
        {name="Bloodmage Thalnos", rare=false, npcID=4543, loot={{id=7685,name="Orb of the Forgotten Seer"},{id=7684,name="Bloodmage Mantle"},{id=274291,name="Polished Skullcap"},{id=252822,name="Pattern: Defender's Leather Kilt"},}},
    },
    ["Shadowfang Keep"] = {
        {name="Rethilgore", rare=false, npcID=3914, loot={{id=5254,name="Rugged Spaulders"},{id=273457,name="Sorcerer Collar"},{id=273456,name="Cell Keeper's Claws"},}},
        {name="Fel Steed / Shadow Charger", rare=false, npcID=3864, loot={{id=6341,name="Eerie Stable Lantern"},{id=932,name="Fel Steed Saddlebags"},{id=251341,name="Plans: Guard's Chain Shirt"},{id=251362,name="Plans: Protector's Gloves"},{id=251363,name="Plans: Acolyte's Gloves"},{id=251364,name="Plans: Crusader's Gloves"},{id=252781,name="Pattern: Stormrider's Leather Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},{id=253902,name="Pattern: Filigreed Pristine Gown"},{id=253904,name="Pattern: Filigreed Silky Gown"},{id=253906,name="Pattern: Filigreed Flame Gown"},{id=253908,name="Pattern: Filigreed Shadow Gown"},{id=253910,name="Pattern: Filigreed Pearly Gown"},{id=253912,name="Pattern: Filigreed Shining Gown"},{id=251381,name="Plans: Guard's Silvered Chain Helm"},{id=251382,name="Plans: Protector's Silvered Chain Helm"},{id=252799,name="Pattern: Trapper's Leather Hood"},{id=252801,name="Pattern: Totemic Leather Hood"},{id=252803,name="Pattern: Wisdom's Leather Hood"},{id=253940,name="Pattern: Filigreed Silky Leggings"},{id=253946,name="Pattern: Filigreed Pearly Leggings"},{id=253948,name="Pattern: Filigreed Shining Leggings"},}},
        {name="Razorclaw the Butcher", rare=false, npcID=3886, loot={{id=1292,name="Butcher's Cleaver"},{id=6226,name="Bloody Apron"},{id=6633,name="Butcher's Slicer"},}},
        {name="Baron Silverlaine", rare=false, npcID=3887, loot={{id=6321,name="Silverlaine's Family Seal"},{id=6323,name="Baron's Scepter"},{id=273637,name="Blade of Silverlaine"},}},
        {name="Commander Springvale", rare=false, npcID=4278, loot={{id=6320,name="Commander's Crest"},{id=3191,name="Arced War Axe"},{id=273643,name="Worgenbane Talisman"},{id=6341,name="Eerie Stable Lantern"},}},
        {name="Odo the Blindwatcher", rare=false, npcID=4279, loot={{id=6318,name="Odo's Ley Staff"},{id=6319,name="Girdle of the Blindwatcher"},{id=273645,name="Blindwatcher's Sight"},}},
        {name="Deathsworn Captain", rare=true, npcID=3872, loot={{id=6642,name="Phantom Armor"},{id=6641,name="Haunting Blade"},}},
        {name="Arugal's Voidwalker", rare=false, npcID=4627, loot={{id=5943,name="Rift Bracers"},}},
        {name="Fenrus the Devourer", rare=false, npcID=4274, loot={{id=6340,name="Fenrus' Hide"},{id=3230,name="Black Wolf Bracers"},{id=273646,name="Half-Eaten Boots"},}},
        {name="Wolf Master Nandos", rare=false, npcID=3927, loot={{id=3748,name="Feline Mantle"},{id=6314,name="Wolfmaster Cape"},{id=273647,name="Worgpelt Leggings"},}},
        {name="Archmage Arugal", rare=false, npcID=4275, loot={{id=6324,name="Robes of Arugal"},{id=6392,name="Belt of Arugal"},{id=6220,name="Meteor Shard"},}},
    },
    ["The Deadmines"] = {
        {name="Rhahk'Zor", rare=false, npcID=644, loot={{id=872,name="Rockslicer"},{id=5187,name="Rhahk'Zor's Hammer"},{id=273289,name="Ogre Loincloth"},{id=251362,name="Plans: Protector's Gloves"},{id=251364,name="Plans: Crusader's Gloves"},{id=253906,name="Pattern: Filigreed Flame Gown"},}},
        {name="Miner Johnson", rare=true, npcID=3586, loot={{id=5443,name="Gold-plated Buckler"},{id=5444,name="Miner's Cape"},}},
        {name="Sneed's Shredder", rare=false, npcID=642, loot={{id=1937,name="Buzz Saw"},{id=2169,name="Buzzer Blade"},{id=285292,name="Dull Sawblade"},}},
        {name="Sneed", rare=false, npcID=643, loot={{id=5194,name="Taskmaster Axe"},{id=5195,name="Gold-flecked Gloves"},{id=273293,name="Bandsaw Wristbands"},{id=273092,name="Blueprint: Repair Bot"},{id=251360,name="Plans: Veteran's Gloves"},{id=251364,name="Plans: Crusader's Gloves"},{id=253902,name="Pattern: Filigreed Pristine Gown"},}},
        {name="Gilnid", rare=false, npcID=1763, loot={{id=1156,name="Lavishly Jeweled Ring"},{id=5199,name="Smelting Pants"},{id=273297,name="Goblin Hammer"},{id=252777,name="Pattern: Brawler's Leather Gloves"},{id=252778,name="Pattern: Trapper's Leather Gloves"},{id=252780,name="Pattern: Totemic Leather Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},{id=253904,name="Pattern: Filigreed Silky Gown"},{id=253906,name="Pattern: Filigreed Flame Gown"},{id=273086,name="Blueprint: Anvil"},}},
        {name="Mr. Smite", rare=false, npcID=646, loot={{id=7230,name="Smite's Mighty Hammer"},{id=5192,name="Thief's Blade"},{id=5196,name="Smite's Reaver"},{id=284715,name="First Mate Band"},{id=251362,name="Plans: Protector's Gloves"},{id=252779,name="Pattern: Defender's Leather Gloves"},{id=252780,name="Pattern: Totemic Leather Gloves"},{id=252781,name="Pattern: Stormrider's Leather Gloves"},{id=252782,name="Pattern: Wisdom's Leather Gloves"},}},
        {name="Captain Greenskin", rare=false, npcID=647, loot={{id=5201,name="Emberstone Staff"},{id=10403,name="Blackened Defias Belt"},{id=5200,name="Impaling Harpoon"},}},
        {name="Edwin VanCleef", rare=false, npcID=639, loot={{id=5193,name="Cape of the Brotherhood"},{id=5202,name="Corsair's Overshirt"},{id=10399,name="Blackened Defias Armor"},{id=5191,name="Cruel Barb"},{id=2874,name="An Unsent Letter"},{id=252799,name="Pattern: Trapper's Leather Hood"},{id=252800,name="Pattern: Defender's Leather Hood"},{id=252801,name="Pattern: Totemic Leather Hood"},{id=252803,name="Pattern: Wisdom's Leather Hood"},{id=253938,name="Pattern: Filigreed Pristine Leggings"},{id=253948,name="Pattern: Filigreed Shining Leggings"},}},
        {name="Cookie", rare=false, npcID=645, loot={{id=5198,name="Cookie's Stirring Rod"},{id=5197,name="Cookie's Tenderizer"},{id=273298,name="Lookie's Spyglass"},{id=251360,name="Plans: Veteran's Gloves"},{id=252778,name="Pattern: Trapper's Leather Gloves"},{id=252779,name="Pattern: Defender's Leather Gloves"},{id=253910,name="Pattern: Filigreed Pearly Gown"},{id=253912,name="Pattern: Filigreed Shining Gown"},{id=273102,name="Blueprint: Cookie's Feast"},}},
    },
    ["The Stockade"] = {
        {name="Targorr the Dread", rare=false, npcID=1696, loot={{id=273805,name="Blackrock Harness"},{id=273804,name="Executioner Mantle"},{id=273806,name="Dark Horde Band"},{id=251380,name="Plans: Veteran's Silvered Chain Helm"},{id=251382,name="Plans: Protector's Silvered Chain Helm"},{id=253942,name="Pattern: Filigreed Flame Leggings"},}},
        {name="Kam Deepfury", rare=false, npcID=1666, loot={{id=2280,name="Kam's Walking Stick"},{id=273807,name="Demolition Girdle"},{id=273808,name="Bridgebreaker Bindings"},{id=251379,name="Plans: Crusader's Silvered Chain Leggings"},{id=252825,name="Pattern: Wisdom's Leather Leggings"},}},
        {name="Hamhock", rare=false, npcID=1717, loot={{id=273809,name="Hamhock's Cleaver"},{id=273810,name="Ogre Grips"},{id=273811,name="Repurposed Rack"},{id=251377,name="Plans: Protector's Silvered Chain Leggings"},}},
        {name="Dextren Ward", rare=false, npcID=1663, loot={{id=273817,name="Graverobber's Shovel"},{id=273819,name="Boneslicer"},{id=273820,name="Nightskulker Ring"},{id=251375,name="Plans: Veteran's Silvered Chain Leggings"},{id=251376,name="Plans: Guard's Silvered Chain Leggings"},{id=252820,name="Pattern: Brawler's Leather Legguards"},{id=252821,name="Pattern: Trapper's Leather Legguards"},}},
        {name="Bazil Thredd", rare=false, npcID=1716, loot={{id=273827,name="Debt Collector"},{id=273824,name="Defias Jailbreakers"},{id=273825,name="Red Wool Cloak"},{id=273829,name="Concealed Hand Crossbow"},{id=252824,name="Pattern: Stormrider's Leather Kilt"},{id=253976,name="Pattern: Filigreed Pristine Circlet"},{id=253986,name="Pattern: Filigreed Shining Circlet"},}},
        {name="Bruegal Ironknuckle", rare=true, npcID=1720, loot={{id=3228,name="Jimmied Handcuffs"},{id=2941,name="Prison Shank"},{id=2942,name="Iron Knuckles"},}},
    },
    ["Wailing Caverns"] = {
        {name="Lord Cobrahn", rare=false, npcID=3669, loot={{id=6460,name="Cobrahn's Grasp"},{id=10410,name="Leggings of the Fang"},{id=6465,name="Robe of the Moccasin"},}},
        {name="Lady Anacondra", rare=false, npcID=3671, loot={{id=10412,name="Belt of the Fang"},{id=5404,name="Serpent's Shoulders"},{id=6446,name="Snakeskin Bag"},{id=273088,name="Snake Eye Kaleidoscope"},}},
        {name="Kresh", rare=false, npcID=3653, loot={{id=13245,name="Kresh's Back"},{id=6447,name="Worn Turtle Shell Shield"},{id=273084,name="Cloak of Hermitic Bliss"},}},
        {name="Lord Pythas", rare=false, npcID=3670, loot={{id=6472,name="Stinging Viper"},{id=6473,name="Armor of the Fang"},{id=273089,name="Slither Cord"},}},
        {name="Skum", rare=false, npcID=3674, loot={{id=6449,name="Glowing Lizardscale Cloak"},{id=6448,name="Tail Spike"},{id=273137,name="Skum's Bucket"},}},
        {name="Lord Serpentis", rare=false, npcID=3673, loot={{id=6469,name="Venomstrike"},{id=5970,name="Serpent Gloves"},{id=10411,name="Footpads of the Fang"},{id=6459,name="Savage Trodders"},}},
        {name="Verdan the Everliving", rare=false, npcID=5775, loot={{id=6630,name="Seedcloud Buckler"},{id=6631,name="Living Root"},{id=6629,name="Sporid Cape"},}},
        {name="Mutanus the Devourer", rare=false, npcID=3654, loot={{id=6461,name="Slime-encrusted Pads"},{id=6627,name="Mutant Scale Breastplate"},{id=6463,name="Deep Fathom Ring"},{id=10441,name="Glowing Shard"},}},
        {name="Deviate Faerie Dragon", rare=true, npcID=5912, loot={{id=5243,name="Firebelcher"},{id=6632,name="Feyscale Cloak"},{id=252781,name="Pattern: Stormrider's Leather Gloves"},}},
    },
}
GambleData.journalAuditedInstances = {}
for instanceName,bosses in pairs(journalBosses) do
    local resolved=instanceName:gsub("Scarlet Monastery: ","Scarlet Monastery ")
    for _,boss in ipairs(bosses) do
        if boss.name=="The Baron" then boss.aliases={"The Butcher"} end
        if boss.name=="Fel Steed / Shadow Charger" then boss.aliases={"Fel Steed","Shadow Charger"} end
    end
    GambleData.instances[resolved]=bosses
    GambleData.journalAuditedInstances[resolved]=true
end
