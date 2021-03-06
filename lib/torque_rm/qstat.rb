require 'date'
require 'time'
require 'json'
require 'json/add/core'
require 'ostruct'
require 'time_diff'

module TORQUE
  class Qstat
#DEPRECATED    # FIELDS = %w(job_id job_name job_owner resources_used_cput resources_used_mem resources_used_vmem 
    #            resources_used_walltime job_state substate queue server checkpoint ctime error_path exec_host
    #            exec_port hold_types join_path keep_files mail_points mail_users mtime output_path
    #            priority qtime rerunable resource_list session_id shell_path_list variable_list 
    #            euser egroup hashname queue_rank queue_type comment etime
    #            exit_status submit_args walltime_remaining start_time start_count fault_tolerant comp_time job_radix total_runtime
    #            submit_host nppcu)
    # Job = Struct.new(:job_id, :job_name, :job_owner, :resources_used_cput, :resources_used_mem, :resources_used_vmem,
    #        :resources_used_walltime, :job_state, :substate, :queue, :server, :checkpoint, :ctime, :error_path, :exec_host,
    #        :exec_port, :hold_types, :join_path, :keep_files, :mail_points, :mail_users, :mtime, :output_path,
    #        :priority, :qtime, :rerunable, :resource_list, :session_id,
    #        :shell_path_list, :variable_list, :euser, :egroup, :hashname, :queue_rank, :queue_type, :comment,
    #        :etime, :exit_status, :submit_args, :walltime_remaining, :start_time,
    #        :start_count, :fault_tolerant, :comp_time, :job_radix, :total_runtime, :submit_host, :nppcu) do
    class EnanchedOpenStruct < OpenStruct
      def initialize(*args)
        super(*args)
        casting
        alias_case_insensitive_methods
      end

      private

      # Cast generic types from string to most near type selected by pattern matching
      def casting
        @table.each_pair do |k,v| #converting
          if v =~ (/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)
            hours,minutes,seconds = v.split(':')
            now = Time.now
            send "#{k}=", Time.diff(now, now-((hours.to_i/24)*(24*3600))-((hours.to_i%24)*3600)-(minutes.to_i*60)-(seconds.to_i)) #time_diff object
          elsif k.to_s =~ /time/ && v.is_a?(String) && v =~ (/^[0-9]+$/)
            send "#{k}=", Time.at(v.to_i).to_datetime
          elsif v =~ (/(true)$/i)
            send "#{k}=", true
          elsif v =~ (/(false)$/i)
            send "#{k}=", false
          elsif v =~ (/^[0-9]+$/)
            send "#{k}=", v.to_i
          elsif v.is_a? Hash
            send "#{k}=", EnanchedOpenStruct.new(v)
          end
        end #each pair        
      end #casting

      def alias_case_insensitive_methods
        @table.each_pair do |k,v| #adding methods
          unless k == k.downcase
            original=k.to_sym
            newer=k.downcase.to_sym
            class_eval do
              alias_method newer, original 
              alias_method "#{newer}=", "#{original}="
            end
          end
        end
      end

    end

    class Job < EnanchedOpenStruct
      #add here your custom method for Qstat::Job


      def initialize(*args)
        super(*args)
        class_eval do
          alias_method :id, :job_id
        end
      end

      def is_runnig?
        job_state == 'R'
      end
      alias running? is_runnig?

      def is_completed?
        job_state == 'C'
      end
      alias completed? is_completed?

      def is_exited?
        job_state == 'E'
      end
      alias exited? is_exited?

      def is_queued?
        job_state == 'Q'
      end
      alias queued? is_queued?
      alias is_in_queue? is_queued?

      def time
				return (resources_used && resources_used.walltime) ? resources_used.walltime[:diff] : "-" #using time_diff it prints a nice report in case of more than 1 day
      end

      def memory
        (resources_used && resources_used.mem) ? (resources_used.mem.split("kb").first.to_f/1000).round(1) : "0"
      end

      def node 
        exec_host ? exec_host.split("+").map {|n| n.split(".").first}.uniq.join(",") : "-"
      end

			def procs
				if resource_list.ncpus
					return resource_list.ncpus
				elsif resource_list.nodes
          if resource_list.nodes.is_a? String
					  return resource_list.nodes.split("ppn=")[-1]
          else
            return resource_list.nodes
          end
				else
    			return "-"
        end
			end

      def fields
        FIELDS + %w( is_runnig? is_queued? is_exited? is_completed? time memory node )
      end

      def self.fields
        FIELDS + %w( is_runnig? is_queued? is_exited? is_completed? time memory node )
      end

      #alias to_hash to_h

      def to_map
        map = Hash.new
        self.members.each { |m| map[m] = self[m] }
        map
      end

      def to_json(*a)
        to_map.to_json(*a)
      end

      def self.json_load(json)
        JSON.load(json)
      end

      def rm
        Qdel.rm(job_id)
      end
      alias :del :rm
      alias :delete :rm

    end # Job

    # class Parser < Parslet::Parser
    #   rule(:newline)          { match('\n').repeat(1) }
    #   rule(:space)            { match('\s').repeat }
    #   rule(:space?)           { space.maybe }
    #   rule(:tab)              { match('\t').repeat(1) }
    #   rule(:newline?)         { newline.maybe }
    #   rule(:value)            { match('[a-zA-Z0-9\.\_\@\/\+ \,\-:=]').repeat }
    #   rule(:qstat)            { job_id.repeat }
    #   rule(:resource_list_name)    { str("Resource_List") >> str(".") >> (match('[a-zA-Z]').repeat(1).as(:string)).as(:name) }
    #   rule(:split_assignment) { (space >> str("=") >> space).repeat(1) }
    #   root(:qstat)

    #   rule(:variable_item){ tab >> value >> newline }
    #   rule(:variable_items) { variable_item.repeat }
    #   rule(:variable_list_items) { value >> newline >> variable_items.maybe}


    #   rule(:job_id)                  {(str("Job Id:") >> space >> value.as(:string)).as(:job_id) >> newline? >> fields.maybe >> newline? }
    #   rule(:job_name)                {(space >> str("Job_Name = ") >> value.as(:string) >> newline).as(:job_name)}
    #   rule(:job_owner)               {(space >> str("Job_Owner = ") >> value.as(:string) >> newline).as(:job_owner)}
    #   rule(:resources_used_cput)     {(space >> str("resources_used.cput = ") >> value.as(:string) >> newline).as(:resources_used_cput)}
    #  	rule(:resources_used_mem)      {(space >> str("resources_used.mem = ") >> value.as(:string) >> newline).as(:resources_used_mem)}
    #  	rule(:resources_used_vmem)     {(space >> str("resources_used.vmem = ") >> value.as(:string) >> newline).as(:resources_used_vmem)}
    #  	rule(:resources_used_walltime) {(space >> str("resources_used.walltime = ") >> value.as(:string) >> newline).as(:resources_used_walltime)}
    #  	rule(:job_state)               {(space >> str("job_state = ") >> value.as(:string) >> newline).as(:job_state)}
    #  	rule(:queue)                   {(space >> str("queue = ") >> value.as(:string) >> newline).as(:queue)}
    #  	rule(:server)                  {(space >> str("server = ") >> value.as(:string) >> newline).as(:server)}
    #  	rule(:checkpoint)              {(space >> str("Checkpoint = ") >> value.as(:string) >> newline).as(:checkpoint)}
    #  	rule(:ctime)                   {(space >> str("ctime = ") >> value.as(:datetime) >> newline).as(:ctime)}
    #  	rule(:error_path)              {(space >> str("Error_Path = ") >> value.as(:string) >> newline).as(:error_path)}
    #  	rule(:exec_host)               {(space >> str("exec_host = ") >> value.as(:string) >> newline).as(:exec_host)}
    #  	rule(:exec_port)               {(space >> str("exec_port = ") >> value.as(:string) >> newline).as(:exec_port)}
    #  	rule(:hold_types)              {(space >> str("Hold_Types = ") >> value.as(:string) >> newline).as(:hold_types)}
    #  	rule(:join_path)               {(space >> str("Join_Path = ") >> value.as(:string) >> newline).as(:join_path)}
    #  	rule(:keep_files)              {(space >> str("Keep_Files = ") >> value.as(:string) >> newline).as(:keep_files)}
    #  	rule(:mail_points)             {(space >> str("Mail_Points = ") >> value.as(:string) >> newline).as(:mail_points)}
    #  	rule(:mail_users)              {(space >> str("Mail_Users = ") >> value.as(:string) >> newline).as(:mail_users)}
    #  	rule(:mail_users?)             {mail_users.maybe }
    #  	rule(:mtime)                   {(space >> str("mtime = ") >> value.as(:datetime) >> newline).as(:mtime)}
    #  	rule(:output_path)             {(space >> str("Output_Path = ") >> value.as(:string) >> newline).as(:output_path)}
    #  	rule(:priority)                {(space >> str("Priority = ") >> value.as(:integer) >> newline).as(:priority)}
    #  	rule(:qtime)                   {(space >> str("qtime = ") >> value.as(:datetime) >> newline).as(:qtime)}
    #  	rule(:rerunable)               {(space >> str("Rerunable = ") >> value.as(:boolean) >> newline).as(:rerunable)}

    #   rule(:resource)                {(space >> resource_list_name >> str(" = ") >> (value.as(:string)).as(:value) >> newline).as(:resource)}
    #   rule(:resource_list)           { resource.repeat.as(:resource_list)}

    #  	rule(:session_id)              {(space >> str("session_id = ") >> value.as(:integer) >> newline?).as(:session_id)}
    #   rule(:substate)                {(space >> str("substate = ") >> value.as(:integer) >> newline?).as(:substate)} # Torque 2.4.16
    #  	rule(:shell_path_list)         {(space >> str("Shell_Path_List = ") >> value.as(:string) >> newline?).as(:shell_path_list)}
    #   rule(:variable_list)           {(space >> str("Variable_List = ") >> variable_list_items.as(:string) >> newline?).as(:variable_list)}
    #   rule(:euser)                   {(space >> str("euser = ") >> value.as(:string) >> newline?).as(:euser)} # Torque 2.4.16
    #   rule(:egroup)                  {(space >> str("egroup = ") >> value.as(:string) >> newline?).as(:egroup)} # Torque 2.4.16
    #   rule(:hashname)                {(space >> str("hashname = ") >> value.as(:string) >> newline?).as(:hashname)} # Torque 2.4.16
    #   rule(:queue_rank)              {(space >> str("queue_rank = ") >> value.as(:string) >> newline?).as(:queue_rank)} # Torque 2.4.16
    #   rule(:queue_type)              {(space >> str("queue_type = ") >> value.as(:string) >> newline?).as(:queue_type)} # Torque 2.4.16
    #   rule(:comment)                 {(space >> str("comment = ") >> value.as(:string) >> newline?).as(:comment)} # Torque 2.4.16
    #  	rule(:etime)                   {(space >> str("etime = ") >> value.as(:datetime) >> newline?).as(:etime)}
    #   rule(:exit_status)             {(space >> str("exit_status = ") >> value.as(:string) >> newline?).as(:exit_status)}
    #  	rule(:submit_args)             {(space >> str("submit_args = ") >> value.as(:string) >> newline?).as(:submit_args)}
    #  	rule(:start_time)              {(space >> str("start_time = ") >> value.as(:datetime) >> newline?).as(:start_time)}
    #   rule(:walltime_remaining)      {(space >> str("Walltime.Remaining = ") >> value.as(:integer) >> newline?).as(:walltime_remaining)} # Torque 2.4.16
    #  	rule(:start_count)             {(space >> str("start_count = ") >> value.as(:integer) >> newline?).as(:start_count)}
    #  	rule(:fault_tolerant)          {(space >> str("fault_tolerant = ") >> value.as(:boolean) >> newline?).as(:fault_tolerant)}
    #   rule(:comp_time)               {(space >> str("comp_time = ") >> value.as(:datetime) >> newline?).as(:comp_time)}
    #  	rule(:job_radix)               {(space >> str("job_radix = ") >> value.as(:string) >> newline?).as(:job_radix)}
    #   rule(:total_runtime)           {(space >> str("total_runtime = ") >> value.as(:string) >> newline?).as(:total_runtime)}
    #  	rule(:submit_host)             {(space >> str("submit_host = ") >> value.as(:string) >> newline?).as(:submit_host)}
    #   rule(:nppcu)                   {(space >> str("nppcu = ") >> value.as(:integer) >> newline?).as(:nppcu)} #Torque 4.2.5 / Maui 3.3.1

    # # a lot of maybe, maybe everything

    #   rule(:fields) { job_name.maybe >> job_owner.maybe >> resources_used_cput.maybe >> resources_used_mem.maybe >> 
    #        resources_used_vmem.maybe >> resources_used_walltime.maybe >>  job_state.maybe >> queue.maybe  >> server.maybe >> 
    #       checkpoint.maybe >> ctime.maybe >> error_path.maybe >> exec_host.maybe >> exec_port.maybe >> hold_types.maybe  >> 
    #       join_path.maybe >>  keep_files.maybe >> mail_points.maybe >> mail_users.maybe >> mtime.maybe >> output_path.maybe >>
    #       tab.maybe >> newline? >> priority.maybe >> qtime.maybe >> rerunable.maybe >> 
    #       resource_list.maybe >> session_id.maybe >> substate.maybe >> shell_path_list.maybe >>
    #       variable_list.maybe >> 
    #       euser.maybe >> egroup.maybe >> hashname.maybe >> 
    #       queue_rank.maybe >> queue_type.maybe >> 
    #       comment.maybe >> etime.maybe >> exit_status.maybe >> 
    #       submit_args.maybe >> start_time .maybe >>
    #       walltime_remaining.maybe >> start_count.maybe >> fault_tolerant.maybe >> comp_time.maybe >> job_radix.maybe >> total_runtime.maybe >> 
    #       submit_host.maybe >> nppcu.maybe >>
    #       newline?
    #         }


    # end #Parser

    # class Trans < Parslet::Transform
    #   rule(:datetime => simple(:datetime)) {DateTime.parse(datetime)}
    #   rule(:string => simple(:string))     {String(string)}
    #   rule(:integer => simple(:integer))   {Integer(integer)}
    #   rule(:boolean => simple(:boolean))   {String(boolean) == "True"}
    # end #Trans


    def initialize
        # @parser = Parser.new #DEPRECATED
        # @transformer = Trans.new #DEPRECATED
        @last_query = nil #cache last query, it can be useful to generate some kind of statistics ? 
    end #initialize
 
    def self.fields
      FIELDS
    end

    def fields
      FIELDS
    end

    # hash can contain keys:
    # type = :raw just print a string
    # job_id = job.id it will print info only about the specified job
    # job_ids = ["1.server", "2.server", "3.server"] get an array for requested jobs
    # returns results which is an Array of Job
    def query(hash={})
        # result = TORQUE.server.qstat('-f')
        if hash[:type] == :raw
          TORQUE.server.qstat('-f').to_s  #returns
        elsif hash[:type] == :xml
          TORQUE.server.qstat('-f','-x')  #returns
        else
          # begin
            data_xml = Hash.from_xml(TORQUE.server.qstat('-f','-x').to_s)
            @last_query = if data_xml.nil?
              [] #returns
            else
              data_array = data_xml["Data"]["Job"].is_a?(Hash) ? [data_xml["Data"]["Job"]] : data_xml["Data"]["Job"]
              jobs = data_array.map do |job_xml|
                Job.new job_xml
              end # do
              if hash.key? :job_id
                # if hash[:job_id]..is_a? String
                  jobs.select {|job| (hash[:job_id].to_s == job.job_id || hash[:job_id].to_s == job.job_id.split(".").first)}
                # else
                  # warn "You gave me #{hash[:job_id].class}, only String is supported."
                # end
              elsif hash.key? :job_ids
                if hash[:job_ids].is_a? Array
                  jobs.select {|job| (hash[:job_ids].include?(job.job_id) || hash[:job_ids].include?(job.job_id.split(".").first))}
                elsif hash[:job_ids].is_a? String
                  warn "To be implemented for String object."
                else
                  warm "To be implemented for #{hash[:job_ids].class}"
                end 
              else
                jobs
              end
            end # else

            # puts result.to_s.inspect
            # puts result.to_s.gsub(/\n\t/,'').inspect
            # results = @transformer.apply(@parser.parse(result.to_s.gsub(/\n\t/,'')))
          # rescue Parslet::ParseFailed => failure
          #   puts failure.cause.ascii_tree
          # end

          # results = [] if results.is_a?(String) && results.empty?
        # @last_query = from_parselet_to_jobs(results)
        end
    end #query

    def display(hash={})
      query(hash)
      print_jobs_table(@last_query)
    end

    def mock(results)
      from_parselet_to_jobs(results)
    end


private

    def from_parselet_to_jobs(results)
        results.map do |raw_job|
          job = Job.new
           raw_job.each_pair do |key, value|
              job.send "#{key}=", value
          end #each pair
          job
        end #each_job
    end

    def print_jobs_table(jobs_info)  
			rows = []
      head = ["Job ID","Job Name","Node(s)","Procs (per node)","Mem Used","Run Time","Queue","Status"]
      headings = head.map {|h| {:value => h, :alignment => :center}}
      if jobs_info.empty?
        print "\n\nNo Running jobs for user: ".light_red+"#{`whoami`}".green+"\n\n"
      	# exit
			else
        jobs_info.each do |job|
          line = [job.job_id.split(".").first,job.job_name,job.node,job.procs,"#{job.memory} mb","#{job.time}",job.queue,job.job_state]
          # puts line.inspect
          # puts line[-1]
          if job.completed?
            line[-1] = "Completed"; rows << line.map {|l| l.to_s.underline}
          elsif job.queued?
            line[-1] = "Queued"; rows << line.map {|l| l.to_s.light_blue}
          elsif job.running?
            line[-1] = "Running"; rows << line.map {|l| l.to_s.green}
          elsif job.exited?
            line[-1] = "Exiting"; rows << line.map {|l| l.to_s.green.blink}
          else
            rows << line.map {|l| l.to_s.red.blink}
          end  
        end
        print "\nSummary of submitted jobs for user: ".light_blue+"#{jobs_info.first.job_owner.split("@").first.green}\n\n"
        table = Terminal::Table.new :headings => headings, :rows => rows
      	Range.new(0,table.number_of_columns-1).to_a.each {|c| table.align_column(c,:center) } # set all columns alignment to :center
				puts table
      end

    end

  end # Qstat
end # TORQUE
