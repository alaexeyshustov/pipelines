RSpec.shared_examples 'requires attribute' do |attribute, factory|
  it "requires #{attribute}" do
    record = build(factory, attribute => nil)
    expect(record).not_to be_valid
    expect(record.errors[attribute]).not_to be_empty
  end
end

RSpec.shared_examples 'rejects invalid attribute value' do |attribute, factory, invalid_value|
  it "rejects invalid value for #{attribute}" do
    record = build(factory, attribute => invalid_value)
    expect(record).not_to be_valid
    expect(record.errors[attribute]).not_to be_empty
  end
end

RSpec.shared_examples 'accepts valid statuses' do |factory, statuses|
  it 'accepts valid statuses' do
    statuses.each do |s|
      record = build(factory, status: s)
      expect(record).to be_valid
    end
  end
end

RSpec.shared_examples 'enforces position uniqueness scoped to' do |factory, scope_attribute, scope_factory|
  it "enforces position uniqueness scoped to #{scope_attribute}" do
    scope = create(scope_factory)
    create(factory, scope_attribute => scope, position: 1)
    duplicate = build(factory, scope_attribute => scope, position: 1)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).not_to be_empty
  end

  it "allows same position in different #{scope_attribute}s" do
    create(factory, scope_attribute => create(scope_factory), position: 1)
    other = build(factory, scope_attribute => create(scope_factory), position: 1)
    expect(other).to be_valid
  end
end
