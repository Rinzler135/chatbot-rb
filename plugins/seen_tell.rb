require_relative '../plugin'

class SeenTell
  include Chatbot::Plugin

  match /^seenon/, :method => :enable_seen
  match /^seenoff/, :method => :disable_seen
  match /^tell ([^ ]+) (.+)/, :method => :tell
  match /^seen (.*)/, :method => :seen_user
  match /^tellon/, :method => :enable_tell
  match /^telloff/, :method => :disable_tell
  match /.*/, :method => :update_user, :use_prefix => false
  listen_to :join, :update_user

  # @param [Chatbot::Client] bot
  def initialize(bot)
    super(bot)
    if File.exists? 'tells.yml'
      @tells = YAML::load_file 'tells.yml'
    else
      File.open('tells.yml', 'w+') {|f| f.write({}.to_yaml)}
      @tells = {}
    end
    if File.exists? 'seen.yml'
      @seen = YAML::load_file 'seen.yml'
    else
      File.open('seen.yml', 'w+') {|f| f.write({}.to_yaml)}
      @seen = {}
    end
    @tell_mutex = Mutex.new
    @allow_seen = @client.config[:allow_seen]
    @allow_tell = @client.config[:allow_tell]
  end

  # @param [User] user
  def enable_tell(user)
    if user.is? :mod and !@allow_tell
      @allow_tell = true
      @client.send_msg user.name + ': !tell is now enabled'
    end
  end

  # @param [User] user
  def disable_tell(user)
    if user.is? :mod and @allow_tell
      @allow_tell = false
      @client.send_msg user.name + ': !tell is now disabled'
    end
  end

  # @param [User] user
  # @param [String] target
  # @param [String] message
  def tell(user, target, message)
    return unless @allow_tell
    target.gsub!(/_/, ' ')
    if target.downcase.eql? user.name.downcase
      return @client.send_msg user.name + ': You can\'t !tell yourself something!'
    elsif target.downcase.eql? @client.config['user'].downcase
      return @client.send_msg user.name + ': Thanks for the message <3'
    elsif !@client.config[:allow_tell_to_present_users] and @client.userlist.keys.collect {|name| name.downcase}.include? target.downcase
      return @client.send_msg user.name + ': They\'re already here, go tell them yourself!'
    end
    @tell_mutex.synchronize do
      if @tells.key? target.downcase
        @tells[target.downcase][user.name] = message
      else
        @tells[target.downcase] = {user.name => message}
      end
      File.open('tells.yml', File::WRONLY) {|f| f.write(@tells.to_yaml)}
      @client.send_msg "#{user.name}: I'll tell #{target} that the next time I see them."
    end
  end

  # @param [User] user
  # @param [String] target
  def seen_user(user, target)
    return unless @allow_seen
    if @client.userlist.keys.collect {|name| name.downcase}.include? target.downcase and !@client.config[:seen_use_last_post]
      @client.send_msg "#{user.name}: They're here right now!"
    elsif @seen.key? target.downcase
      @client.send_msg "#{user.name}: I last saw #{target} #{get_hms(Time.now.to_i - @seen[target.downcase])}"
    else
      @client.send_msg "#{user.name}: I haven't seen #{target}"
    end
  end

  # @param [User] user
  def enable_seen(user)
    if user.is? :mod and !@allow_seen
      @allow_seen = true
      @client.send_msg "#{user.name}: !seen enabled"
    end
  end

  # @param [User] user
  def disable_seen(user)
    if user.is? :mod and @allow_seen
      @allow_seen = false
      @client.send_msg "#{user.name}: !seen disabled"
    end
  end

  def fix_tell_file
    File.open('tells.yml', 'w+') {|f| f.write({'foo' => {'bar' => 'baz'}}.merge(@tells).to_yaml)}
  end

  def update_user(*args)
    if args.size > 1 # Message
      user = args[0]
      if !@tells.nil? and @tells.key? user.name.downcase
        @tell_mutex.synchronize do
          @tells[user.name.downcase].each do |k, v|
            @client.send_msg "#{user.name}, #{k} told you: #{v}"
          end
          @tells[user.name.downcase] = {}
          File.open('tells.yml', 'w+') {|f| f.write(@tells.to_yaml)}
        end
      elsif @tells.nil?
        fix_tell_file
      end
      @seen[user.name.downcase] = Time.now.to_i
      File.open('seen.yml', File::WRONLY) {|f| f.write(@seen.to_yaml)}
    else
      user = @client.userlist[args[0]['attrs']['name']]
      return if @client.config[:seen_use_last_post]
      @seen[user.name.downcase] = Time.now.to_i
      File.open('seen.yml', File::WRONLY) {|f| f.write(@seen.to_yaml)}
    end
  end

  # @param [FixNum] ts
  # @return [String]
  def get_hms(ts)
    weeks = ts / 604800
    ts %= 604800
    days = ts / 86400
    ts %= 86400
    hours = ts / 3600
    ts %= 3600
    minutes = ts / 60
    ts %= 60
    ret = ''
    ret += "#{weeks} week#{weeks > 1 ? 's' : ''}, " if weeks > 0
    ret += "#{days} day#{days > 1 ? 's' : ''}, " if days > 0
    ret += "#{hours} hour#{hours > 1 ? 's' : ''}, " if hours > 0
    ret += "#{minutes} minute#{minutes > 1 ? 's' : ''}, " if minutes > 0
    ret.gsub(/, $/, ' and ') + "#{ts} second#{ts != 1 ? 's' : ''} ago."
  end
end
