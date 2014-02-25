# Class to help Logger output to both STOUT and to a file
class MultiIO

    def initialize(*targets)
        @targets = targets
	@msg_count_hash = Hash.new (0)
	@time_first = "nil"
	@time_last = "nil"
    end

    def write(*args)
        @targets.each {|t| t.write(*args)}
	@msg_count_hash[args[0][0..0]] += 1
	@time_first = args[0][4..22] if @time_first == "nil"

    end

    def close
        @targets.each(&:close)
    end

    def get_msg_stats
        return @msg_count_hash
    end

    def get_time_first
        return @time_first
    end
end

class Logger
    def show_msg_stats
	info "Logger summary:"
        @logdev.dev.get_msg_stats.each do |level, count|
	    if count > 0 then
	        info "\t#{count} #{{'D'=>'DEBUG','I'=>'INFO','W'=>'WARN','E'=>'ERROR','F'=>'FATAL','U'=>'UNKNOWN'}[level]}"
	    end
	end
	info "\tStarted @ #{@logdev.dev.get_time_first}"
    end
end
