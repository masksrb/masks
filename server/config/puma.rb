threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart

plugin :solid_queue if Masks.to_bool(ENV["MASKS_JOBS_IN_WEB_SERVER"], default: true)

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
