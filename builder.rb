require 'docker'
require 'yaml'
require './slack'

class Builder
  @queue     = ENV.fetch('BUILDER_QUEUE', :builder_queue) # resque queue
  @home      = ENV.fetch('BUILDER_HOME', '/tmp')          # where to clone repos
  @registry  = ENV.fetch('BUILDER_REGISTRY', nil)         # set this to your private registry
  @files_dir = ENV.fetch('BUILDER_FILES', File.join(File.dirname(File.expand_path(__FILE__)), 'files')) # dir for extra files to deliver into repos
  @github_token = ENV['GITHUB_TOKEN']

  def self.perform(params)
    repo = OpenStruct.new(params)

    ## authenticate to private registry
    if @registry
      Docker.authenticate!(
        username:      ENV['BUILDER_REGISTRY_USERNAME'],
        password:      ENV['BUILDER_REGISTRY_PASSWORD'],
        email:         ENV.fetch('BUILDER_REGISTRY_EMAIL', 'builder@example.com'),
        serveraddress: "https://#{@registry}/v1/"
      )
    end

    ## prevent timeout on docker api operations (e.g. long bundle install during build)
    Excon.defaults[:write_timeout] = ENV.fetch('DOCKER_WRITE_TIMEOUT', 1000)
    Excon.defaults[:read_timeout]  = ENV.fetch('DOCKER_READ_TIMEOUT',  1000)

    ## for tag and dir we need to replace / in branch
    branch = repo.branch.gsub('/', '-')

    ## clone with https if we have a token, otherwise ssh and depends on ssh keys being set up
    repo.url ||= @github_token ? "https://#{@github_token}@github.com/#{repo.org}/#{repo.name}.git" : "git@github.com:#{repo.org}/#{repo.name}.git"

    ## where to clone the repo
    repo.dir ||= File.join(@home, repo.org, "#{repo.name}:#{branch}")

    Resque.logger.info "pulling #{repo.url}"
    repo.sha = git_pull(repo)

    ## copy any external files into the repo
    copy_files(File.join(@files_dir, repo.name), repo.name)

    ## link to commit to embed into slack messages
    sha_link = "<http://github.com/#{repo.org}/#{repo.name}/commit/#{repo.sha}|#{repo.sha.slice(0,10)}>"

    ## load config from file or default is a single build in top-level of repo
    yaml = load_yaml(File.join(repo.dir, '.builder.yml')) || {}
    builds = yaml.fetch('builds', [{
      'dir'   => '.',
      'image' => [ @registry, "#{repo.name}" ].compact.join('/')
    }])

    ## do all requested builds
    builds.each do |build|
      image = build['image']
      Resque.logger.info "building image #{image}:#{branch}"

      begin
        ## build the image
        img = Docker::Image.build_from_dir(File.join(repo.dir, build['dir']), dockerfile: build.fetch('dockerfile', 'Dockerfile')) do |chunk|
          stream = JSON.parse(chunk)['stream']
          unless (stream.nil? || stream.match(/^[\s\.]+$/)) # very verbose about build progress
            Resque.logger.info stream.chomp
          end
        end

        ## tag and push
        if img.is_a?(Docker::Image)
          notify_slack("build complete for #{image}:#{branch} #{sha_link}", :good)

          Resque.logger.info "tagging #{image}:#{branch}"
          img.tag(repo: image, tag: repo.sha, force: true)
          img.tag(repo: image, tag: branch,   force: true)

          Resque.logger.info "pushing #{image}:#{branch}"
          img.push(nil, tag: repo.sha)
          img.push(nil, tag: branch)

          notify_slack("push complete for #{image}:#{branch} #{sha_link}", :good)
        else
          notify_slack("build failed for #{image}:#{branch} #{sha_link}", :danger)
        end
      rescue => e
        notify_slack("error for #{image}:#{branch}: #{e.message}", :danger)
      end

      Resque.logger.info "done #{image}:#{branch}"
    end
  end

  ## load optional yaml file listing subdirs to build
  def self.load_yaml(file)
    if File.exists?(file)
      Resque.logger.info "found builder file #{file}"
      YAML.load_file(file)
    end
  end

  ## update repo and return SHA
  def self.git_pull(repo)
    if %x[ mkdir -p #{repo.dir} && cd #{repo.dir} && git rev-parse --is-inside-work-tree 2> /dev/null ].chomp == 'true'
      git_checkout(repo) #repo exists, pull changes
    else
      git_clone(repo)    #new repo, clone it
    end
    git_rev_parse(repo)  #return SHA
  end

  def self.git_checkout(repo)
    Resque.logger.info "repo exists, pulling #{repo.url}"
    Dir.chdir(repo.dir) do
      %x[ git checkout -f #{repo.branch} && git fetch && git reset --hard origin/#{repo.branch} ]
    end
  end

  def self.git_clone(repo)
    Resque.logger.info "new repo, cloning #{repo.url}"
    %x[ git clone -b #{repo.branch} #{repo.url} '#{repo.dir}' ] # not found: clone it
  end

  def self.git_rev_parse(repo)
    Dir.chdir(repo.dir) do
      %x[ git rev-parse #{repo.branch} ].chomp
    end
  end

  ## if there is a dir of extra files, recursively copy them into repo
  def self.copy_files(files_dir, repo_dir)
    if Dir.exists?(files_dir)
      Resque.logger.info("copying files from #{files_dir} into #{repo_dir}")
      FileUtils.cp_r(File.join(files_dir, '.'), repo_dir)
    end
  end

end
