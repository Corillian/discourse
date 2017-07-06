require_dependency 'memory_diagnostics'

class Admin::DiagnosticsController < Admin::AdminController
  layout false
  skip_before_filter :check_xhr

  def dump_statement_cache
    statements = Post.exec_sql("select * from pg_prepared_statements").to_a
    text = ""

    statements.each do |row|
      text << "name: #{row["name"]} sql: #{row["statement"]}\n"
    end

    text << "\n\nCOUNT #{statements.count}"

    render plain: text
  end

  def memory_stats
    text = nil

    if params.key?(:diff)
      if !MemoryDiagnostics.snapshot_exists?
        text = "No initial snapshot exists"
      else
        text = MemoryDiagnostics.compare
      end
    elsif params.key?(:snapshot)
      MemoryDiagnostics.snapshot_current_process
      text = "Writing snapshot to: #{MemoryDiagnostics.snapshot_filename}\n\nTo get a diff use ?diff=1"
    else
      text = MemoryDiagnostics.memory_report(class_report: params.key?(:full))
    end

    render plain: text
  end

  def dump_heap
    begin
      # ruby 2.1
      GC.start(full_mark: true)
      require 'objspace'

      io = File.open("discourse-heap-#{SecureRandom.hex(3)}.json",'w')
      ObjectSpace.dump_all(:output => io)
      io.close

      render plain: "HEAP DUMP:\n#{io.path}"
    rescue
      render plain: "HEAP DUMP:\nnot supported"
    end
  end

end
