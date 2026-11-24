require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class InitWorktreeTest < Minitest::Test
  SANDBOX = File.expand_path("..", __dir__)
  STUB_BIN = File.expand_path("support", __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir("init-worktree-test"))
    @origin = File.join(@root, "origin.git")
    @repo = File.join(@root, "repo")
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(@home)
    build_repo
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_scratch_worktree_receives_only_the_database_from_the_include_list
    stdout, stderr, status = run_init_worktree

    assert status.success?, "init-worktree failed: #{stderr}"
    worktree = worktree_path(stdout)

    assert File.file?(File.join(worktree, "storage/development.sqlite3")), "database was not copied"
    assert_equal "sqlite", File.read(File.join(worktree, "storage/development.sqlite3"))
  end

  def test_secret_files_stay_out_of_the_worktree
    stdout, stderr, status = run_init_worktree

    assert status.success?, "init-worktree failed: #{stderr}"
    worktree = worktree_path(stdout)

    %w[.env .env.local credentials.json token.yaml].each do |secret|
      refute File.exist?(File.join(worktree, secret)), "#{secret} must not be copied into the worktree"
    end
  end

  private

  def build_repo
    git(@root, "init", "--bare", "-b", "main", @origin)
    git(@root, "init", "-b", "main", @repo)
    git(@repo, "remote", "add", "origin", @origin)

    FileUtils.mkdir_p(File.join(@repo, ".sandbox/bin"))
    %w[init-worktree db_helper db_helper.rb].each do |file|
      FileUtils.cp(File.join(SANDBOX, "bin", file), File.join(@repo, ".sandbox/bin", file))
    end
    File.write(File.join(@repo, "README.md"), "repo\n")
    git(@repo, "add", "-A")
    git(@repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-m", "init")
    git(@repo, "push", "origin", "main")

    # Untracked local files, listed the way the real .worktreeinclude lists them.
    File.write(File.join(@repo, ".worktreeinclude"), <<~LIST)
      .env
      .env.local
      credentials.json
      token.yaml
      storage/development.sqlite3
    LIST
    %w[.env .env.local credentials.json token.yaml].each { |name| File.write(File.join(@repo, name), "secret\n") }
    FileUtils.mkdir_p(File.join(@repo, "storage"))
    File.write(File.join(@repo, "storage/development.sqlite3"), "sqlite")
  end

  def run_init_worktree
    Open3.capture3(
      {
        "HOME" => @home,
        "DB_HELPER_DATABASE_PATH" => File.join(@root, "sandbox.sqlite"),
        "DB_HELPER_REPO_ROOT" => @repo,
        "GIT_CONFIG_GLOBAL" => File.join(@root, "gitconfig"),
        "PATH" => "#{STUB_BIN}:#{ENV.fetch("PATH")}"
      },
      File.join(@repo, ".sandbox/bin/init-worktree"),
      chdir: @repo
    )
  end

  def worktree_path(stdout)
    path = stdout[/^Sandbox worktree ready: (.+)$/, 1]
    flunk "no worktree path in output: #{stdout}" unless path
    path
  end

  def git(directory, *arguments)
    output, status = Open3.capture2e("git", *arguments, chdir: directory)
    raise "git #{arguments.join(" ")} failed: #{output}" unless status.success?
  end
end
