module Evaluation
  # One metric's verdict for one sample. +score+ is already normalized to 0.0..1.0 (nil = unknown).
  # +tokens+ / +cost+ describe the whole judgment call and are carried by the first grade only,
  # so summing grades never double counts.
  Grade = Data.define(:metric_name, :score, :raw, :confidence, :passed, :justification, :tokens, :cost)
end
