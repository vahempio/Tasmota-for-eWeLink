#- Native code used for testing and code solidification -#
#- Do not use it -#

class Trigger
  var trig, f, id
  var o             # optional object
  def init(trig, f, id, o)
    self.trig = trig
    self.f = f
    self.id = id
    self.o = o
  end
  def tostring()
    import string
    return string.format("<instance: %s(%s, %s, %s)", str(classof(self)),
              str(self.trig), str(self.f), str(self.id))
  end
  # next() returns the next trigger, or 0 if rtc is invalid, or nil if no more
  def next()
    if self.o
      return self.o.next()
    end
  end
  
  def time_reached()
    if self.o && self.trig > 0
      return self.o.time_reached(self.trig)
    end
    return false
  end
end

tasmota = nil
class Tasmota
  var _fl             # list of fast_loop registered closures
  var _rules
  var _timers         # holds both timers and cron
  var _crons
  var _ccmd
  var _drivers
  var wire1
  var wire2
  var cmd_res         # store the command result, nil if disables, true if capture enabled, contains return value
  var global          # mapping to TasmotaGlobal
  var settings
  var wd              # when load() is called, `tasmota.wd` contains the name of the archive. Ex: `/M5StickC.autoconf#`
  var _debug_present  # is `import debug` present?

  def init()
    # instanciate the mapping object to TasmotaGlobal
    self.global = ctypes_bytes_dyn(self._global_addr, self._global_def)
    import introspect
    var settings_addr = bytes(self._settings_ptr, 4).get(0,4)
    if settings_addr
      self.settings = ctypes_bytes_dyn(introspect.toptr(settings_addr), self._settings_def)
    end
    self.wd = ""
    self._debug_present = false
    try
      import debug
      self._debug_present = true
    except .. 
    end
  end

  # check that the parameter is not a method, it would require a closure instead
  def check_not_method(f)
    import introspect
    if type(f) != 'function'
      raise "type_error", "BRY: argument must be a function"
    end
    if introspect.ismethod(f) == true
      raise "type_error", "BRY: method not allowed, use a closure like '/ args -> obj.func(args)'"
    end
  end

  # add `chars_in_string(s:string,c:string) -> int``
  # looks for any char in c, and return the position of the first char
  # or -1 if not found
  # inv is optional and inverses the behavior, i.e. look for chars not in the list
  def chars_in_string(s,c,inv)
    var inverted = inv ? true : false
    var i = 0
    while i < size(s)
    # for i:0..size(s)-1
      var found = false
      var j = 0
      while j < size(c)
      # for j:0..size(c)-1
        if s[i] == c[j] found = true end
        j += 1
      end
      if inverted != found return i end
      i += 1
    end
    return -1
  end

  # find a key in map, case insensitive, return actual key or nil if not found
  def find_key_i(m,keyi)
    import string
    var keyu = string.toupper(keyi)
    if isinstance(m, map)
      for k:m.keys()
        if string.toupper(k)==keyu || keyi=='?'
          return k
        end
      end
    end
  end


  # split the item when there is an operator, returns a list of (left,op,right)
  # ex: "Dimmer>50" -> ["Dimmer",tasmota_gt,"50"]
  def find_op(item)
    import string
    var op_chars = '=<>!'
    var pos = self.chars_in_string(item, op_chars)
    if pos >= 0
      var op_split = string.split(item,pos)
      var op_left = op_split[0]
      var op_rest = op_split[1]
      pos = self.chars_in_string(op_rest, op_chars, true)
      if pos >= 0
        var op_split2 = string.split(op_rest,pos)
        var op_middle = op_split2[0]
        var op_right = op_split2[1]
        return [op_left,op_middle,op_right]
      end
    end
    return [item, nil, nil]
  end

  # Rules
  def add_rule(pat, f, id)
    self.check_not_method(f)
    if !self._rules
      self._rules=[]
    end
    if type(f) == 'function'
      self._rules.push(Trigger(pat, f, id))
    else
      raise 'value_error', 'the second argument is not a function'
    end
  end

  def remove_rule(pat, id)
    if self._rules
      var i = 0
      while i < size(self._rules)
        if self._rules[i].trig == pat && self._rules[i].id == id
          self._rules.remove(i)  #- don't increment i since we removed the object -#
        else
          i += 1
        end
      end
    end
  end

  # Rules trigger if match. return true if match, false if not
  def try_rule(event, rule, f)
    import string
    var rl_list = self.find_op(rule)
    var sub_event = event
    var rl = string.split(rl_list[0],'#')
    var i = 0
    while i < size(rl)
    # for it:rl
      var it = rl[i]
      var found=self.find_key_i(sub_event,it)
      if found == nil return false end
      sub_event = sub_event[found]
      i += 1
    end
    var op=rl_list[1]
    var op2=rl_list[2]
    if op
      if   op=='=='
        if str(sub_event) != str(op2)   return false end
      elif op=='!=='
        if str(sub_event) == str(op2)   return false end
      elif op=='='
        if real(sub_event) != real(op2) return false end
      elif op=='!='
        if real(sub_event) == real(op2) return false end
      elif op=='>'
        if real(sub_event) <= real(op2) return false end
      elif op=='>='
        if real(sub_event) < real(op2)  return false end
      elif op=='<'
        if real(sub_event) >= real(op2) return false end
      elif op=='<='
        if real(sub_event) > real(op2)  return false end
      end
    end
    f(sub_event, rl_list[0], event)
    return true
  end

  # Run rules, i.e. check each individual rule
  # Returns true if at least one rule matched, false if none
  # `exec_rule` is true, then run the rule, else just record value
  def exec_rules(ev_json, exec_rule)
    var save_cmd_res = self.cmd_res     # save initial state (for reentrance)
    if self._rules || save_cmd_res != nil  # if there is a rule handler, or we record rule results
      import json
      
      self.cmd_res = nil                  # disable sunsequent recording of results
      var ret = false

      var ev = json.load(ev_json)   # returns nil if invalid JSON
      if ev == nil
        self.log('BRY: ERROR, bad json: '+ev_json, 3)
        ev = ev_json                # revert to string
      end
      # try all rule handlers
      if exec_rule && self._rules
        var i = 0
        while i < size(self._rules)
          var tr = self._rules[i]
          ret = self.try_rule(ev,tr.trig,tr.f) || ret  #- call should be first to avoid evaluation shortcut if ret is already true -#
          i += 1
        end
      end

      # record the rule payload for tasmota.cmd()
      if save_cmd_res != nil
        self.cmd_res = ev
      end

      return ret
    end
    return false
  end

  # Run tele rules
  def exec_tele(ev_json)
    if self._rules
      import json
      var ev = json.load(ev_json)   # returns nil if invalid JSON
      var ret = false
      if ev == nil
        self.log('BRY: ERROR, bad json: '+ev_json, 3)
        ev = ev_json                # revert to string
      end
      # insert tele prefix
      ev = { "Tele": ev }

      var i = 0
      while i < size(self._rules)
        var tr = self._rules[i]
        ret = self.try_rule(ev,tr.trig,tr.f) || ret  #- call should be first to avoid evaluation shortcut -#
        i += 1
      end
      return ret
    end
    return false
  end

  def set_timer(delay,f,id)
    self.check_not_method(f)
    if !self._timers self._timers=[] end
    self._timers.push(Trigger(self.millis(delay),f,id))
  end

  # run every 50ms tick
  def run_deferred()
    if self._timers
      var i=0
      while i < self._timers.size()
        var trigger = self._timers[i]

        if self.time_reached(trigger.trig)
          var f = trigger.f
          self._timers.remove(i)      # one shot event
          f()
        else
          i += 1
        end
      end
    end
  end

  def run_cron()
    if self._crons
      var i=0
      var now = ccronexpr.now()
      while i < self._crons.size()
        var trigger = self._crons[i]

        if trigger.trig == 0        # trigger was created when RTC was invalid, try to recalculate
          trigger.trig = trigger.next()
        elif trigger.time_reached() # time has come
          var f = trigger.f
          var next_time = trigger.next()
          trigger.trig = next_time   # update to next time
          f(now, next_time)
        end
        i += 1
      end
    end
  end

  def remove_timer(id)
    var timers = self._timers
    if timers
      var i=0
      while i < timers.size()
        if timers[i].id == id
          timers.remove(i)
        else
          i=i+1
        end
      end
    end
  end
  
  # crontab style recurring events
  def add_cron(pattern,f,id)
    self.check_not_method(f)
    if !self._crons self._crons=[] end

    var cron_obj = ccronexpr(str(pattern))    # can fail, throwing an exception
    var next_time = cron_obj.next()

    self._crons.push(Trigger(next_time, f, id, cron_obj))
  end

  # remove cron by id
  def remove_cron(id)
    var crons = self._crons
    if crons
      var i=0
      while i < crons.size()
        if crons[i].id == id
          crons.remove(i)
        else
          i=i+1
        end
      end
    end
  end

  # get next timestamp for cron
  def next_cron(id)
    var crons = self._crons
    if crons
      var i=0
      while i < crons.size()
        if crons[i].id == id
          return crons[i].trig
        end
        i += 1
      end
    end
  end

  # Add command to list
  def add_cmd(c,f)
    self.check_not_method(f)
    if !self._ccmd
      self._ccmd={}
    end
    if type(f) == 'function'
      self._ccmd[c]=f
    else
      raise 'value_error', 'the second argument is not a function'
    end
  end

  # Remove command from list
  def remove_cmd(c)
    if self._ccmd
      self._ccmd.remove(c)
    end
  end

  # Execute custom command
  def exec_cmd(cmd, idx, payload)
    if self._ccmd
      import json
      var payload_json = json.load(payload)
      var cmd_found = self.find_key_i(self._ccmd, cmd)  # name of the command as registered (case insensitive search)
      if cmd_found != nil
        self.resolvecmnd(cmd_found)   # set the command name in XdrvMailbox.command as it was registered first
        self._ccmd[cmd_found](cmd_found, idx, payload, payload_json)
        return true
      end
    end
    return false
  end

  # Force gc and return allocated memory
  def gc()
    import gc
    gc.collect()
    return gc.allocated()
  end

  # tasmota.wire_scan(addr:int [, index:int]) -> wire1 or wire2 or nil
  # scan for the first occurrence of the addr, starting with bus1 then bus2
  # optional: skip if index is disabled via I2CEnable
  def wire_scan(addr,idx)
    # skip if the I2C index is disabled
    if idx != nil && !self.i2c_enabled(idx) return nil end
    if self.wire1.enabled() && self.wire1.detect(addr) return self.wire1 end
    if self.wire2.enabled() && self.wire2.detect(addr) return self.wire2 end
    return nil
  end

  def time_str(time)
    import string
    var tm = self.time_dump(time)
    return string.format("%04d-%02d-%02dT%02d:%02d:%02d", tm['year'], tm['month'], tm['day'], tm['hour'], tm['min'], tm['sec'])
  end

  def load(f)
    # embedded functions
    # puth_path: adds the current archive to sys.path
    def push_path(p)
      import sys
      var path = sys.path()
      if path.find(p) == nil  # append only if it's not already there
        path.push(p)
      end
    end
    # pop_path: removes the path
    def pop_path(p)
      import sys
      var path = sys.path()
      var idx = path.find(p)
      if idx != nil
        path.remove(idx)
      end
    end
    # load prefix for bec file and return version nunmber
    # arg: filename with `.bec` suffix
    # returns: version number (int) or nil if error or does not exist
    #    does not raise any exception
    def try_get_bec_version(fname_bec)
      var f
      try
        f = open(fname_bec, "r")
        var f_sign = f.readbytes(3)
        var f_version = f.readbytes(1)
        if f_sign == bytes('BECDFE')
          return f_version[0]
        end
        f.close()
      except .. as e
        if f != nil     f.close() end
        import string
        print(string.format('BRY: failed to load compiled \'%s\' (%s)',fname_bec,e))
      end
      return nil
    end
    # try to delete a file, report errors but don't throw any exception
    def try_remove_file(f_name)
      import path
      try
        return path.remove(f_name)
      except ..
      end
      return false
    end
    # try to compile a file
    # arg: filename
    # returns: compiled code (function) or `nil` if failed
    #   does not raise an exception
    def try_compile(f_name)
      try
        var compiled = compile(f_name, 'file')
        return compiled
      except .. as e, m
        import string
        print(string.format('BRY: failed to load \'%s\' (%s - %s)',f_name,e,m))
      end
      return nil
    end
    # try to run the compiled code
    # arg: compiled code (function) or `nil` if failed
    # returns: `true` if succesful, `false` if code failed
    def try_run_compiled(compiled_code)
      if compiled_code != nil
        try
          compiled_code()
          return true
        except .. as e, m
          import string
          print(string.format("BRY: failed to run compiled code '%s' - %s", e, m))
        end
      end
      return false
    end

    import string
    import path

    # fail if empty string
    if size(f) == 0 return false end
    # Ex: f = 'app.zip#autoexec'

    # add leading '/' if absent
    if f[0] != '/'   f = '/' + f end
    # Ex: f = '/app.zip#autoexec'

    var f_items = string.split(f, '#')
    var f_prefix = f_items[0]
    var f_suffix = f_items[-1]          # last token
    var f_archive = size(f_items) > 1   # is the file in an archive

    # if no dot, add the default '.be' extension
    if string.find(f_suffix, '.') < 0   # does the final file has a '.'
      f += ".be"
      f_suffix += ".be"
    end
    # Ex: f = '/app.zip#autoexec.be'

    # is the suffix .be or .bec ?
    var suffix_be  = f_suffix[-3..-1] == '.be'
    var suffix_bec = f_suffix[-4..-1] == '.bec'
    # Ex: f = '/app.zip#autoexec.be', f_suffix = 'autoexec.be', suffix_be = true, suffix_bec = false

    # check that the file ends with '.be' of '.bec'
    if !suffix_be && !suffix_bec
      raise "io_error", "file extension is not '.be' or '.bec'"
    end

    # get the last_modified time of the file or archive, returns `nil` if the file does not exist
    var f_time = path.last_modified(f)
    var f_name_bec = suffix_bec ? f : f + "c"      # f_name_bec holds the bec version of the filename

    if suffix_bec
      if f_time == nil  return false end      # file requested is .bec but does not exist, fail
      # from now, .bec file does exist
    else
      var f_time_bec = path.last_modified(f_name_bec) # timestamp for .bec bytecode, nil if does not exist
      if f_time == nil && f_time_bec == nil  return false end   # abort if neither .be nor .bec file exist
      if f_time_bec != nil && (f_time == nil || f_time_bec >= f_time)
        # bytecode exists and is more recent than berry source, use bytecode
        ##### temporarily disable loading from bec file
        suffix_bec = true
      end
      # print("f_time",f_time,"f_time_bec",f_time_bec,"suffix_bec",suffix_bec)
    end
    
    # recall the working directory
    if f_archive
      self.wd = f_prefix + "#"
      push_path(self.wd)
    else
      self.wd = ""
    end

    # try to load code into `compiled_code`, or `nil` if didn't succeed
    var compiled_code
    if suffix_bec     # try the .bec version
      # in this section we try to load the pre-compiled bytecode first
      # (we already know that the file exists)
      var bec_version = try_get_bec_version(f_name_bec)
      var version_ok = true
      if bec_version == nil
        print(string.format('BRY: corrupt bytecode \'%s\'',f_name_bec))
        version_ok = false
      elif bec_version != 0x04          # -- this is the currenlty supported version
        print(string.format('BRY: bytecode has wrong version \'%s\' (%i)',f_name_bec,bec_version))
        version_ok = false
      end

      if version_ok
        compiled_code = try_compile(f_name_bec)
      end

      if compiled_code == nil         # bytecode is bad, try to delete it and fallback
        try_remove_file(f_name_bec)
        suffix_bec = false
      end
    end

    if suffix_be && compiled_code == nil
      # the pre-compiled is absent to failed, load the be file instead
      compiled_code = try_compile(f)
    end

    # save the compiled bytecode unless it's an archive
    # print("compiled_code",compiled_code,"suffix_be",suffix_be,"suffix_bec",suffix_bec,"archive",f_archive,"f_name_bec",f_name_bec)
    if compiled_code != nil && !suffix_bec && !f_archive
      # try to save the pre-compiled version
      try
        self.save(f_name_bec, compiled_code)
      except .. as e
        print(string.format('BRY: could not save compiled file %s (%s)',f_name_bec,e))
      end
    end
    # call the compiled code
    var run_ok = try_run_compiled(compiled_code)
    # call successfuls

    # remove path prefix
    if f_archive
      pop_path(f_prefix + "#")
    end

    return run_ok
  end

  # fast_loop() is a trimmed down version of event() called at every Tasmota loop iteration
  # it is optimized to be as fast as possible and reduce overhead
  # there is no introspect, closures must be registered directly
  def fast_loop()
    var fl = self._fl
    if !fl return end     # fast exit if no closure is registered (most common case)

    # iterate and call each closure
    var i = 0
    while i < size(fl)
      # note: this is not guarded in try/except for performance reasons. The inner function must not raise exceptions
      fl[i]()
      i += 1
    end
  end

  def add_fast_loop(cl)
    self.check_not_method(cl)
    if !self._fl  self._fl = [] end
    if type(cl) != 'function' raise "value_error", "argument must be a function" end
    self.global.fast_loop_enabled = 1      # enable fast_loop at global level: `TasmotaGlobal.fast_loop_enabled = true`
    self._fl.push(cl)
  end

  def event(event_type, cmd, idx, payload, raw)
    import introspect
    import string
    if event_type=='every_50ms'
      self.run_deferred()
    end  #- first run deferred events -#

    if event_type=='every_250ms'
      self.run_cron()
    end

    var done = false
    var keep_going = false    # if true, we continue dispatch event if done == true (for mqtt_data)

    if event_type == 'mqtt_data'
      keep_going = true
    end

    if event_type=='cmd' return self.exec_cmd(cmd, idx, payload)
    elif event_type=='tele' return self.exec_tele(payload)
    elif event_type=='rule' return self.exec_rules(payload, bool(idx))
    elif event_type=='gc' return self.gc()
    elif self._drivers
      var i = 0
      while i < size(self._drivers)
        var d = self._drivers[i]
        var f = introspect.get(d, event_type)   # try to match a function or method with the same name
        if type(f) == 'function'
          try
            done = f(d, cmd, idx, payload, raw) || done
            if done && !keep_going   break end
          except .. as e,m
            print(string.format("BRY: Exception> '%s' - %s", e, m))
            if self._debug_present
              import debug
              debug.traceback()
            end
          end
        end
        i += 1
      end
    end

    # save persist
    if event_type=='save_before_restart'
      import persist
      persist.save()
    end

    return done
  end

  def add_driver(d)
    if type(d) != 'instance'
      raise "value_error", "instance required"
    end
    if self._drivers
      self._drivers.push(d)
        else
      self._drivers = [d]
    end
  end

  def remove_driver(d)
    if self._drivers
      var idx = self._drivers.find(d)
      if idx != nil
        self._drivers.pop(idx)
      end
    end
  end

  # cmd high-level function
  def cmd(command)
    var save_cmd_res = self.cmd_res     # restore value on exit (for reentrant)
    self.cmd_res = true      # signal buffer capture

    self._cmd(command)
    
    var ret = nil
    if self.cmd_res != true       # unchanged
      ret = self.cmd_res
    end
    self.cmd_res = save_cmd_res       # restore previous state
    
    return ret
  end

  # set_light and get_light deprecetaion
  def get_light(l)
    print('tasmota.get_light() is deprecated, use light.get()')
    import light
    if l != nil
      return light.get(l)
    else
      return light.get()
    end
  end
  def set_light(v,l)
    print('tasmota.set_light() is deprecated, use light.set()')
    import light
    if l != nil
      return light.set(v,l)
    else
      return light.set(v)
    end
  end

  #- generate a new C callback and record the associated Berry closure -#
  def gen_cb(f)
    # DEPRECATED
    import cb
    return cb.gen_cb(f)
  end

  #- convert hue/sat to rgb -#
  #- hue:int in range 0..359 -#
  #- sat:int (optional) in range 0..255 -#
  #- returns int: 0xRRGGBB -#
  def hs2rgb(hue,sat)
    if sat == nil  sat = 255 end
    var r = 255   # default to white
    var b = 255
    var g = 255
    # we take brightness at 100%, brightness should be set separately
    hue = hue % 360   # normalize to 0..359
  
    if sat > 0
      var i = hue / 60    # quadrant 0..5
      var f = hue % 60    # 0..59
      var p = 255 - sat
      var q = tasmota.scale_uint(f, 0, 60, 255, p)    # 0..59
      var t = tasmota.scale_uint(f, 0, 60, p, 255)
  
      if   i == 0
        # r = 255
        g = t
        b = p
      elif i == 1
        r = q
        # g = 255
        b = p
      elif i == 2
        r = p
        #g = 255
        b = t
      elif i == 3
        r = p
        g = q
        #b = 255
      elif i == 4
        r = t
        g = p
        #b = 255
      else
        #r = 255
        g = p
        b = q
      end
    end
  
    return (r << 16) | (g << 8) | b
  end
end
