DELETE FROM spell_list
WHERE spell_list_id IN
      (328, 323, 348, 389, 374, 310, 390, 308, 317, 326)
  AND (
       (id BETWEEN 33 AND 42)
    OR (id BETWEEN 174 AND 203)
    OR (id BETWEEN 225 AND 229)
    OR (id BETWEEN 273 AND 274)
    OR (id BETWEEN 496 AND 501)
    );