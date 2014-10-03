class PackagingCLI
  require 'rake'
  require 'uri'
  require 'open-uri'

  attr_accessor :repo, :bundle, :remote_bundle, :version, :tasks

  def initialize
    @repo_id = rand(10000000).to_s
    @version = "HEAD"
  end

  # Prepare to execute rake in @repo
  # Behavior depends on which instance variables are set
  def prep_task_environment
    if @repo
      @repo = File.expand_path(@repo)
      check_out_version
      bootstrap
    else
      if @bundle
        @repo = unpack_bundle
      elsif @remote_bundle
        @bundle = retrieve_bundle
      end
      prep_task_environment
    end
  end

  # Bootstrap the packaging repo into @repo
  def bootstrap
    puts "Bootstrapping packaging repo into #{@repo}"
    Dir.chdir(@repo) do
      load("Rakefile")
      Rake::Task["package:bootstrap"].reenable
      Rake::Task["package:bootstrap"].invoke
      unless $?.success?
        fail "Failed to bootstrap the packaging repo into #{@repo}. Make sure this host has access to https://github.com/puppetlabs/packaging"
      end
    end
  end

  # Execute @tasks inside of @repo
  def execute_rake_tasks
    puts "Executing #{@tasks.join(", ")} inside of #{@repo}"
    Dir.chdir(@repo) do
      @tasks.each do |task|
        Rake::Task[task].reenable
        Rake::Task[task].invoke
      end
    end
  end

  # Unpack @bundle in target, temporary dir if nil. Untar if bundle is tarred.
  # Return the path to the unpacked bundle
  def unpack_bundle
    puts "Unpacking #{@bundle}"
    @bundle = File.expand_path(@bundle)
    unless File.exist?(@bundle)
      fail "The file #{@bundle} passed with --bundle does not exist. Pass path to a bundle file with --bundle"
    end
    # The packaging repo tars up git bundles, so we should support untarring if
    # this is the file. I do not like that we're shelling out here. This was a
    # nice class until now.
    #
    # When unpacking the tarball, we'll assume its safe to write the untarred
    # bundle to the tarball's current directory
    bundle_dir = File.dirname(@bundle)
    if @bundle =~ /\.tar\.gz$/
      %x(tar -C #{bundle_dir} -xf #{@bundle})
      unless $?.success?
        fail "Could not untar bundle #{@bundle}. Make sure tar is installed and in your PATH."
      end
      @bundle = @bundle.sub(/\.tar\.gz$/, "")
    end

    # bundles are git repos that are cloned to unpack.
    %x(git clone #{@bundle} #{File.join(bundle_dir, @repo_id)})
    unless $?.success?
      fail "Could not clone the git bundle #{@bundle}. Make sure git is installed and in your PATH."
    end
    File.join(bundle_dir, @repo_id)
  end

  # Retrieve the remote git bundle at URI @remote_bundle
  # Return the local path to the bundle
  def retrieve_bundle
    puts "Retrieving bundle at #{@remote_bundle}"
    uri = URI.parse(@remote_bundle)
    bundle = uri.path
    target = %x(mktemp -d -t pkgXXXXXX).chomp
    unless $?.success?
      fail "Could not create temp dir for bundle download. Make sure mktemp is installed and in your PATH."
    end
    @bundle = File.join(target, bundle)
    File.open(@bundle, 'w') { |f| f.puts( open(uri).read ) }
    @bundle
  end

  # Check out @version in @repo specified by @version
  def check_out_version
    puts "Checking out #{@version} in #{@repo}"
    Dir.chdir(@repo) do
      %x(git checkout #{@version})
      unless $?.success?
        fail "Could not check out #{@version} of project in #{@repo}"
      end
    end
  end
end

