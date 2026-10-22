local _, WP = ...
-- Redridge area-level coverage independently recomputed from all 1,062 quest-associated
-- QuestieDB Vanilla spawn records, NOT only the earlier first-3-per-entity sample.
-- Count = raw quest-associated spawn rows within 0.065 normalized map units of each axis.
-- Quest lists are associations; this is NOT player traffic, PvP odds or exact quest objectives.
WP.questAreaCoverage={
 {zone="redridge",x=.340,y=.080,label="Northern mountain camps",count=61,quests="Blackrock Menace; Blackrock Bounty; Shadow Magic"},
 {zone="redridge",x=.226,y=.360,label="Northwest of Lakeshire",count=37,quests="The Everstill Bridge; A Baying of Gnolls; Underbelly Scales"},
 {zone="redridge",x=.367,y=.370,label="Northbound Lakeshire road",count=31,quests="The Everstill Bridge; A Baying of Gnolls; Blackrock Menace; Underbelly Scales"},
 {zone="redridge",x=.785,y=.430,label="Tower of Ilgalar approach",count=61,quests="Solomon's Law; Wanted: Lieutenant Fangore; Morganth"},
 {zone="redridge",x=.650,y=.557,label="Stonewatch Keep vicinity",count=123,quests="Blackrock Menace; Shadow Magic; Selling Fish; Murloc Poachers; Tharil'zun; Solomon's Law"},
 {zone="redridge",x=.468,y=.716,label="South Lake Everstill shore",count=84,quests="Selling Fish; Murloc Poachers; Assessing the Threat; Underbelly Scales"}
}
