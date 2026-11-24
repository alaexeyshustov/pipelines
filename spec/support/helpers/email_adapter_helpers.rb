# Registers fake mail adapters (real BaseAdapter subclasses with canned answers) behind the Emails facade, so specs
# exercise the real Emails module (and its keyword plumbing) without HTTP or IMAP. Pair with `after { Emails.configure }`.
# Stub several providers in one example by calling the helpers one after another.
module EmailAdapterHelpers
  # Answers the adapter reader methods with the canned values it was built with; anything else raises
  # NotImplementedError like BaseAdapter. Specs can still `allow(fake).to receive(...)` to override a reader.
  class FakeAdapter < Emails::Adapters::BaseAdapter
    READERS = %i[profile account inbox_status inbox_message_ids_since inbox_message_ids_after inbox_uids_after
                 inbox_uids_since fetch_message attachments attachment].freeze

    def initialize(**answers)
      super()
      @answers = answers
    end

    # Each reader takes the parameters of BaseAdapter's method of the same name, so a call (or a stub, which rspec
    # checks against this signature) that BaseAdapter would reject fails here too.
    READERS.each do |reader|
      params = Emails::Adapters::BaseAdapter.instance_method(reader).parameters
      list = params.map do |type, name|
        { req: name.to_s, key: "#{name}: nil", keyreq: "#{name}:" }.fetch(type)
      end.join(", ")
      class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
        def #{reader}(#{list})
          @answers.fetch(:#{reader}) { raise NotImplementedError, "\#{self.class}##{reader} has no canned answer" }
        end
      RUBY
    end
  end

  GMAIL_ACCOUNT = "me@gmail.com".freeze
  YAHOO_ACCOUNT = "me@yahoo.com".freeze

  def stub_gmail_adapter(history_id: "500", **stubs)
    register_adapter(Emails::GMAIL, Emails::Adapters::GmailAdapter,
                     profile: { email_address: GMAIL_ACCOUNT, history_id: history_id }, **stubs)
  end

  def stub_yahoo_adapter(uid_validity: 777, last_uid: 20, **stubs)
    status = Emails::Adapters::ImapInboxReader::Status.new(uid_validity:, last_uid:)
    register_adapter(Emails::YAHOO, Emails::Adapters::YahooAdapter, account: YAHOO_ACCOUNT, inbox_status: status, **stubs)
  end

  # A provider whose credentials are missing: the registry raises Emails::NotConfigured when it is first used.
  def stub_unconfigured_adapter(provider)
    klass = Emails::PROVIDERS.fetch(provider)
    allow(klass).to receive(:from_env).and_raise(Emails::NotConfigured, "#{provider} is not configured")
    configure_emails
  end

  # The hash Adapter#fetch_message returns.
  def adapter_message(id, provider: Emails::GMAIL, date: Time.utc(2026, 3, 1, 12), **overrides)
    { id: id, provider: provider, from: "hr@acme.com", to: "me@example.com", subject: "Subject #{id}", date: date,
      body: "Body #{id}", html_body: nil, source_url: nil, **overrides }
  end

  private

  def register_adapter(provider, klass, **stubs)
    adapter = FakeAdapter.new(**stubs)
    FakeAdapter::READERS.each { |reader| allow(adapter).to receive(reader).and_call_original } # so specs can use have_received
    allow(klass).to receive(:from_env).and_return(adapter)
    (@configured_email_providers ||= []) << provider.to_sym
    configure_emails
    adapter
  end

  def configure_emails
    Emails.configure(**(@configured_email_providers || []).index_with { {} })
  end
end
