require "fileutils"
require "openssl"

# The user-supplied part of ~/.config/pipelines-sandbox: a dedicated P-256 CA
# (PKCS#8 key) and a fine-grained GitHub token. Everything is fake and written
# into a temporary HOME. Not a *_test.rb file, so the suite loop skips it.
module SandboxFixtures
  PAT = "github_pat_test".freeze

  module_function

  def state_dir(home) = File.join(home, ".config", "pipelines-sandbox")

  # Creates the state directory (700), ca/ca-cert.pem, ca/ca-key.pem (600) and
  # gh-token (600). Returns the state directory.
  def install(home, token: PAT)
    dir = state_dir(home)
    FileUtils.mkdir_p(File.join(dir, "ca"))
    File.chmod(0o700, File.join(home, ".config"), dir)
    write_ca(File.join(dir, "ca"))
    write_secret(File.join(dir, "gh-token"), "#{token}\n")
    dir
  end

  def write_ca(ca_dir)
    key, certificate = generate_ca
    File.write(File.join(ca_dir, "ca-cert.pem"), certificate.to_pem)
    write_secret(File.join(ca_dir, "ca-key.pem"), key.private_to_pem)
  end

  def write_secret(path, contents)
    File.write(path, contents)
    File.chmod(0o600, path)
  end

  # A self-signed P-256 CA. `private_to_pem` writes PKCS#8 (BEGIN PRIVATE KEY).
  def generate_ca(common_name: "pipelines-sandbox test CA", ca: true)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    name = OpenSSL::X509::Name.parse("/CN=#{common_name}")
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = rand(1..2**32)
    certificate.subject = certificate.issuer = name
    certificate.public_key = key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new(certificate, certificate)
    certificate.add_extension(extensions.create_extension("basicConstraints", ca ? "CA:TRUE" : "CA:FALSE", true))
    certificate.sign(key, OpenSSL::Digest.new("SHA256"))
    [key, certificate]
  end
end
