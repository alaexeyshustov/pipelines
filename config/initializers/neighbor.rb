# Vector columns and nearest-neighbour queries (see Embedding). Requires sqlite_vec and loads it on every SQLite
# connection; distances use sqlite-vec's vec_distance_cosine.
Neighbor::SQLite.initialize!
