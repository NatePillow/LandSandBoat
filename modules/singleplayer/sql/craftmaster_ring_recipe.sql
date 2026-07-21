-- Craftmaster's Ring (item 28586) — craftable, one high-level ingredient per craft.
-- One each of: Orichalcum Ingot, Adaman Ingot, Beech Lumber, X-Potion,
--             Antlion Arrowhead, Wamoura Cloth, Peiste Leather, Sole Sushi.
-- The ring already exists in the base data (item_basic/item_equipment/item_mods
-- + the addon item_list), so only the recipe row is needed.
--
-- Cols: ID, Desynth, KeyItem, Wood,Smith,Gold,Cloth,Leather,Bone,Alchemy,Cook,
--       Crystal, HQCrystal, Ingredient1-8, Result, HQ1, HQ2, HQ3, Qty x4, Name, tag
INSERT INTO `synth_recipes` VALUES (99998,0,0,80,80,80,80,80,80,80,80,4102,4244,747,655,709,4120,2648,2289,2538,5149,28586,28586,28586,28586,1,1,1,1,'Craftmaster''s Ring',NULL);
