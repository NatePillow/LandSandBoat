UPDATE mob_droplist SET groupRate = 1000 WHERE groupRate > 0;
UPDATE mob_droplist SET itemRate = 1000 WHERE itemRate <= 1000 AND itemRate > 150;
UPDATE mob_droplist SET itemRate = 750 WHERE itemRate <= 150 AND itemRate > 50;
UPDATE mob_droplist SET itemRate = 500 WHERE itemRate <= 50 AND itemRate > 0;

UPDATE mob_droplist SET itemRate = 100 WHERE itemId >= 4606 AND itemId <= 5106;
UPDATE mob_droplist SET itemRate = 100 WHERE itemId in (12417, 12673, 12801, 12929,
                                                        12448, 12704, 12832, 12960,
                                                        12728, 12984, 12472, 12856,
                                                        12456, 12712, 12840, 12968,
                                                        12739, 12867, 12995,
                                                        12473, 12729, 12857, 12985,
                                                        12443, 12699, 12827, 12955,
                                                        12457, 12713, 12841, 12969,
                                                        12424, 12808, 12680, 12936,
                                                        12442, 12698, 12826, 12954,
                                                        12458, 12714, 12842, 12970,
                                                        12944, 12432, 12688, 12816,
                                                        12441, 12697, 12825, 12953,
                                                        12833, 12449, 12961, 12705,
                                                        12817, 12433, 12689, 12945,
                                                        12474, 12730, 12858, 12986,
                                                        12416, 12672, 12800, 12928,
                                                        12475, 12731, 12859, 12987,
                                                        12450, 12706, 12836, 12962);