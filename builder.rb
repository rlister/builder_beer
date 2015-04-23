require './slack'
require 'yaml'

class Builder
  @queue     = ENV.fetch('BUILDER_QUEUE', :builder_queue) # resque queue
  @home      = ENV.fetch('BUILDER_HOME', '/tmp')          # where to clone repos
  @docker    = ENV.fetch('BUILDER_DOCKER', 'sudo docker') # how to run docker
  @registry  = ENV.fetch('BUILDER_REGISTRY', nil)         # set this to your private registry
  @files_dir = ENV.fetch('BUILDER_FILES', File.join(File.dirname(File.expand_path(__FILE__)), 'files')) # dir for extra files to deliver into repos

  def self.perform(params)
    repo = OpenStruct.new(params)

    ## for tag and dir we need to remove / from branch
    branch = repo.branch.gsub('/', '-')

    repo.url ||= "git@github.com:#{repo.org}/#{repo.name}.git"
    repo.dir ||= File.join(@home, repo.org, "#{repo.name}:#{branch}")

    Resque.logger.info "building from #{repo.url}"

    ## pull the repo
    repo.sha = git_pull(repo)

    ## copy any external files into the repo
    copy_files(File.join(@files_dir, repo.name), repo.name)

    ## link to commit to embed into slack messages
    sha_link = "<http://github.com/#{repo.org}/#{repo.name}/commit/#{repo.sha}|#{repo.sha.slice(0,10)}>"

    ## load config from file or default
    yaml = load_yaml(File.join(repo.dir, '.builder.yml')) || {}
    builds = yaml.fetch('builds', [{
      'dir'   => '.',
      'image' => [ @registry, "#{repo.name}" ].compact.join('/')
    }])

    ## do all requested builds
    builds.each do |build|

      image_with_sha    = "#{build['image']}:#{repo.sha}" # image to build, tagged with sha
      image_with_branch = "#{build['image']}:#{branch}"   # add branch as a tag

      ## build the image
      build_ok = docker_build(File.join(repo.dir, build['dir']), image_with_sha, build.fetch('dockerfile', 'Dockerfile'))
      notify_slack("build #{build_ok ? 'complete' : 'failed'} for #{image_with_branch} #{sha_link}", build_ok)

      ## add extra tag and push to registry
      if build_ok
        docker_tag(image_with_sha, image_with_branch)
        push_ok = docker_push(image_with_sha) && docker_push(image_with_branch)
        notify_slack("push #{push_ok ? 'complete' : 'failed'} for #{image_with_branch} #{sha_link}", push_ok)
      end

      Resque.logger.info "done #{image_with_sha}"
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

  ## build image, return true/false for success/fail
  def self.docker_build(dir, image, dockerfile)
    Resque.logger.info "building image #{image} in #{dir}"
    Dir.chdir(dir) do
      %x[ #{@docker} build --rm -t #{image} -f #{dockerfile} . ]
      $?.success?
    end
  end

  ## add a tag to image
  def self.docker_tag(image, name)
    Resque.logger.info "tagging image #{image} as #{name}"
    %x[ #{@docker} tag #{image} #{name} ]
    $?.success?
  end

  ## push image to registry
  def self.docker_push(image)
    Resque.logger.info "pushing image #{image}"
    %x[ #{@docker} push #{image} ]
    $?.success?
  end

end
