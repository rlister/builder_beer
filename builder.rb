class Builder
  @queue  = ENV.fetch('BUILDER_QUEUE', :builder_queue)
  @home   = ENV.fetch('BUILDER_HOME', '/tmp')                # where to clone repos
  @docker = ENV.fetch('BUILDER_DOCKER', 'sudo docker')       # how to run docker

  ## spec looks like org/repo:branch, image tag will be same unless passed
  ## as second arg (e.g. for private repo like index.example.com/repo:branch)
  def self.perform(spec, image = nil)
    Resque.logger.info "building #{spec}"

    repo = parse_uri(spec)
    repo.image = image || "#{repo.name}:#{repo.branch}"

    git_pull(repo)
    docker_build(repo)
    docker_push(repo)

    Resque.logger.info "done #{spec}"
  end

  ## need to replace this with a proper git url parser and not assume github
  def self.parse_uri(repospec)
    name, branch = repospec.gsub(/\.git$/, '').split(':')
    branch ||= 'master'
    OpenStruct.new(
      name:   name,
      branch: branch,
      dir:    File.join(@home, "#{name}:#{branch}")
    )
  end

  ## need to replace github assumption
  def self.git_pull(repo)
    if %x[ mkdir -p #{repo.dir} && cd #{repo.dir} && git rev-parse --is-inside-work-tree 2> /dev/null ].chomp == 'true'
      git_checkout(repo) #repo exists, pull changes
    else
      git_clone(repo)    #new repo, clone it
    end
  end

  def self.git_checkout(repo)
    Resque.logger.info 'repo exists, pulling ...'
    Dir.chdir(repo.dir) do
      %x[ git checkout #{repo.branch} && git pull ]
    end
  end

  def self.git_clone(repo)
    Resque.logger.info 'new repo, cloning ...'
    %x[ git clone -b #{repo.branch} git@github.com:#{repo.name} '#{repo.dir}' ] # not found: clone it
  end

  def self.docker_build(repo)
    Resque.logger.info 'building image ...'
    Dir.chdir(repo.dir) do
      %x[ #{@docker} build --rm -t #{repo.image} . ]
    end
  end

  def self.docker_push(repo)
    Resque.logger.info 'pushing image ...'
    %x[ #{@docker} push #{repo.image} ]
  end

end
