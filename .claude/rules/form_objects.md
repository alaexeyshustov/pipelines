---
paths:
  - "app/forms/*.rb"
  - "app/forms/**/*.rb"
---

# Form Objects Development Rules

Form Objects encapsulate the data, validations, and persistence logic for a single UI form, especially when the submission spans multiple models or requires virtual attributes that don't belong in the database.
They act as the bridge between the user's raw input and your domain models.

## Core Principles

1. **Quack like ActiveRecord** – Form objects must seamlessly integrate with Rails standard view helpers (`form_with`) and controllers. They must respond to `valid?`, `save`, and expose an `errors` object.
2. **Context-Specific Validations** – Put validations here that apply *only* to this specific UI interaction (e.g., "Accept Terms of Service" checkbox), keeping the underlying domain models pure.
3. **Transactional Saves** – If a form touches multiple models, the persistence step must be wrapped in an `ActiveRecord::Base.transaction`.
4. **No Side Effects** – Form objects validate input and update the database. If a form submission needs to trigger emails, charge credit cards, or hit APIs, the form should either be called *by* a Service, or return successfully so the Controller can invoke the Service.

## The Standard Interface

Use: `ActiveModel::Model` for lifecycle and validations, and `ActiveModel::Attributes` for type coercion.

```ruby
# WRONG - Controller handling multiple models, complex params, and custom validation
class UsersController < ApplicationController
  def create
    @user = User.new(user_params)
    @company = Company.new(company_params)
    
    if params[:terms_accepted] == "1" && @user.valid? && @company.valid?
      User.transaction do
        @user.save!
        @company.owner = @user
        @company.save!
      end
      redirect_to root_path
    else
      # Messy error handling
    end
  end
end

# RIGHT - Form Object handling the orchestration
class UsersController < ApplicationController
  def new
    @form = RegistrationForm.new
  end

  def create
    @form = RegistrationForm.new(registration_params)
    
    if @form.save
      # Form is valid and DB is updated. Trigger side-effects if needed.
      WelcomeUser.call(user: @form.user) 
      redirect_to root_path
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

## Implementation

Form objects should be strictly organized to ensure they are easy to read and maintain.

```ruby
# app/forms/registration_form.rb
class RegistrationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # 1. Attributes (with type coercion)
  attribute :email, :string
  attribute :password, :string
  attribute :company_name, :string
  attribute :terms_accepted, :boolean, default: false

  # 2. Validations
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }
  validates :company_name, presence: true
  validates :terms_accepted, acceptance: true

  # 3. Public state exposure (so controllers/services can access the created records)
  attr_reader :user, :company

  # 4. Public API
  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      persist!
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    # Promote underlying model errors up to the form object
    promote_errors(e.record)
    false
  end

  private

  # 5. Private Implementation
  def persist!
    @user = User.create!(email: email, password: password)
    @company = Company.create!(name: company_name, owner: @user)
  end

  def promote_errors(record)
    record.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end
end
```

## Handling Existing Records

When a form is used to *edit* existing records, pass the primary record into initialization and delegate its attributes.

```ruby
class ProfileForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_reader :user

  attribute :first_name, :string
  attribute :last_name, :string
  attribute :newsletter_opt_in, :boolean

  def initialize(user:, **kwargs)
    @user = user
    super(
      first_name: user.first_name,
      last_name: user.last_name,
      newsletter_opt_in: user.preference&.newsletter_opt_in,
      **kwargs
    )
  end

  def save
    # ... validation and persistence ...
  end
end
```

## Quick Reference

| Do                                      | Don't                                             |
|-----------------------------------------|---------------------------------------------------|
| `include ActiveModel::Attributes`       | `def email=(val)` boilerplate                     |
| Return `true` or `false` from `#save`   | Return arbitrary objects or strings               |
| Expose `#errors` object                 | Raise exceptions for expected validation failures |
| Wrap multi-model saves in `transaction` | Leave database in partial state on failure        |
| Put UI-only validations here            | Put database integrity rules here                 |

## Common Mistakes

1. **Re-inventing `valid?`** - Don't write a custom `#validate` method. Rely on `ActiveModel::Validations`.
2. **Side Effects in `save`** – Putting application side-effects (e.g., Stripe API calls, background jobs) inside the `save` method. The form's job is *data integrity and persistence*. Move side-effects to a Service object.
3. **Ignoring nested errors** - If an underlying ActiveRecord `#save!` fails in your transaction, the form object needs to catch that and map the errors back to its own `errors` object so the view can render them.
4. **Bypassing strong parameters** – You still need strong parameters in your controller. Do not pass `params` directly to `Form.new`; pass `registration_params`.

**Remember:** Form objects decouple the UI's shape from the Database's shape. They ensure controllers remain thin and models remain focused on core domain rules.
