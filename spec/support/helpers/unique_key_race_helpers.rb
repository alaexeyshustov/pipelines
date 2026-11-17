# Simulates a concurrent insert of the same unique key: the uniqueness validation passes, then the INSERT fails.
module UniqueKeyRaceHelpers
  # The first #save of a +model+ record built from now on raises ActiveRecord::RecordNotUnique; later saves run.
  def raise_not_unique_on_first_save(model)
    raised = false
    allow(model).to receive(:new).and_wrap_original do |new, *args, &block|
      new.call(*args, &block).tap do |record|
        allow(record).to receive(:save).and_wrap_original do |save, **options|
          next save.call(**options) if raised

          raised = true
          raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed"
        end
      end
    end
  end
end
