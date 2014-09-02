require './slack'

class Builder
  @queue     = ENV.fetch('BUILDER_QUEUE', :builder_queue) # resque queue
  @home      = ENV.fetch('BUILDER_HOME', '/tmp')          # where to clone repos
  @docker    = ENV.fetch('BUILDER_DOCKER', 'sudo docker') # how to run docker
  @registry  = ENV.fetch('BUILDER_REGISTRY', nil)         # set this to your private registry
  @files_dir = ENV.fetch('BUILDER_FILES', File.join(File.dirname(File.expand_path(__FILE__)), 'files')) # dir for extra files to deliver into repos

  def self.perform(params)
    repo = OpenStruct.new(params)

    repo.image  ||= [ @registry, "#{repo.name}:#{repo.branch}" ].compact.join('/') #tag with branch
    repo.url    ||= "git@github.com:#{repo.org}/#{repo.name}.git"
    repo.dir    ||= File.join(@home, repo.org, "#{repo.name}:#{repo.branch}")

    Resque.logger.info "building #{repo.image} from #{repo.url}"

    repo.sha = git_pull(repo)
    repo.tag = [ @registry, "#{repo.name}:#{repo.sha}" ].compact.join('/') #tag with sha

    copy_files(repo)
    build_ok = docker_build(repo)
    notify_slack(repo, "build #{build_ok ? 'complete' : 'failed'}")

    if build_ok
      push_ok = docker_push(repo)
      notify_slack(repo, "push #{push_ok ? 'complete' : 'failed'}")
    end

    Resque.logger.info "done #{repo.image}"
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
      %x[ git checkout #{repo.branch} && git pull ]
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
  def self.copy_files(repo)
    dir = File.join(@files_dir, repo.name)
    if Dir.exists?(dir)
      Resque.logger.info("copying files from #{dir} into #{repo.dir}")
      FileUtils.cp_r(File.join(dir, '.'), repo.dir)
    end
  end

  ## build image, tag with sha and branch, return true/false for success/fail
  def self.docker_build(repo)
    Resque.logger.info "building image #{repo.image}"
    Dir.chdir(repo.dir) do
      # %x[ #{@docker} build --rm -t #{repo.image} . ]
      %x[ #{@docker} build --rm -t #{repo.tag} . && #{@docker} tag #{repo.tag} #{repo.image} ]
      $?.success?
    end
  end

  def self.docker_push(repo)
    Resque.logger.info "pushing image #{repo.tag}"
    %x[ #{@docker} push #{repo.tag} ]
    Resque.logger.info "pushing image #{repo.image}"
    %x[ #{@docker} push #{repo.image} ]
    $?.success?
  end

end
