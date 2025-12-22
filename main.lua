-- =========================
-- Scheduler (Roblox-friendly)
-- =========================
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
	return setmetatable({
		ready = {},     -- {co, args}
		timers = {},    -- {wake_time, co}
	}, Scheduler)
end

function Scheduler:spawn(fn, ...)
	local co = coroutine.create(fn)
	table.insert(self.ready, {co, {...}})
	return co
end

function Scheduler:_resume(co, args)
	local ok, why, a, b, c = coroutine.resume(co, table.unpack(args or {}))
	if not ok then error(why, 0) end
	return why, a, b, c
end

function Scheduler:sleep(seconds)
	local co = coroutine.running()
	table.insert(self.timers, {time() + seconds, co})
	return coroutine.yield("sleep")
end

function Scheduler:_wake_due_timers()
	if #self.timers == 0 then return end
	local now = time()

	local i = 1
	while i <= #self.timers do
		local t = self.timers[i]
		if t[1] <= now then
			local co = t[2]
			table.remove(self.timers, i)
			table.insert(self.ready, {co, {true}})
		else
			i += 1
		end
	end
end

function Scheduler:_next_timer_dt()
	if #self.timers == 0 then return nil end
	local soonest = math.huge
	for i = 1, #self.timers do
		soonest = math.min(soonest, self.timers[i][1])
	end
	local dt = soonest - time()
	if dt < 0 then dt = 0 end
	return dt
end

function Scheduler:run()
	self._running = true

	while self._running do
		self:_wake_due_timers()

		if #self.ready > 0 then
			local item = table.remove(self.ready, 1)
			local co, args = item[1], item[2]
			self:_resume(co, args)
		else
			local dt = self:_next_timer_dt()
			task.wait(dt or 0.03)
		end
	end
end

function Scheduler:stop()
	self._running = false
end


-- =========================
-- Channel "último valor" (buffer de 1, sobrescribe)
-- =========================
local Channel = {}
Channel.__index = Channel

function Channel.new(sched)
	return setmetatable({
		sched = sched,

		-- en vez de buf = {}, usamos 1 slot
		hasValue = false,
		value = nil,

		recvq = {}, -- cola de coroutines esperando
	}, Channel)
end

-- send: si hay alguien esperando, entrégale DIRECTO.
-- si no, guarda SOLO el más reciente (sobrescribe).
function Channel:send(v)
	if #self.recvq > 0 then
		local rco = table.remove(self.recvq, 1)
		table.insert(self.sched.ready, {rco, {v}})
		return true
	end

	self.value = v
	self.hasValue = true
	return true
end

-- recv: si hay valor guardado, dalo y vacía el slot.
-- si no, espera.
function Channel:recv()
	if self.hasValue then
		self.hasValue = false
		local v = self.value
		self.value = nil
		return v
	end

	local co = coroutine.running()
	table.insert(self.recvq, co)
	return coroutine.yield("wait_chan")
end

-- opcional: "peek" sin consumir
function Channel:peek()
	if self.hasValue then
		return self.value
	end
	return nil
end

return {
	Scheduler = Scheduler,
	Channel = Channel,
}
