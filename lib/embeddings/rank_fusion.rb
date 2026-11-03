module Embeddings
  # Reciprocal rank fusion: merges several best-first id lists into one. An id scores the sum of
  # 1 / (k + rank) over the lists that contain it (rank is 1-based; k = 60 is the usual damping constant).
  module RankFusion
    module_function

    # [[id, score], ...], highest score first.
    def call(*rankings, k: 60)
      scores = Hash.new(0.0)
      rankings.each { |ids| ids.each_with_index { |id, index| scores[id] += 1.0 / (k + index + 1) } }
      scores.sort_by.with_index { |(_id, score), position| [ -score, position ] }
    end
  end
end
