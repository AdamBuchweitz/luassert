-- module will return spy table, and register its assertions with the main assert engine
local assert = require('luassert.assert')
local util = require('luassert.util')

-- Spy metatable
local spy_mt = {
  __call = function(self, ...)
    local arguments = {...}
    arguments.n = select('#',...)  -- add argument count for trailing nils
    table.insert(self.calls, arguments)
    return self.callback(...)
  end }

local spy   -- must make local before defining table, because table contents refers to the table (recursion)
spy = {
  _ = {"don't care"},

  new = function(callback)
    if not util.callable(callback) then
      error("Cannot spy on type '" .. type(callback) .. "', only on functions or callable elements", 2)
    end
    local s = setmetatable(
    {
      calls = {},
      callback = callback,

      target_table = nil, -- these will be set when using 'spy.on'
      target_key = nil,

      revert = function(self)
        if not self.reverted then
          if self.target_table and self.target_key then
            self.target_table[self.target_key] = self.callback
          end
          self.reverted = true
        end
        return self.callback
      end,

      called = function(self, times, compare)
        if times or compare then
          local compare = compare or function(count, expected) return count == expected end
          return compare(#self.calls, times), #self.calls
        end

        return (#self.calls > 0), #self.calls
      end,

      called_with = function(self, args)
        local function deepcompare(t1, t2)
          for k1,v1 in pairs(t1) do
            local v2 = t2[k1]
            if v2 == nil or v2 ~= spy._ and not util.deepcompare(v1,v2) then
              return false
            end
          end
          for k2,_ in pairs(t2) do
            if t1[k2] == nil then return false end
          end
          return true
        end
        for _,v in ipairs(self.calls) do
          if deepcompare(v, args) then
            return true
          end
        end
        return false
      end
    }, spy_mt)
    assert:add_spy(s)  -- register with the current state
    return s
  end,

  is_spy = function(object)
    return type(object) == "table" and getmetatable(object) == spy_mt
  end,

  on = function(target_table, target_key)
    local s = spy.new(target_table[target_key])
    target_table[target_key] = s
    -- store original data
    s.target_table = target_table
    s.target_key = target_key

    return s
  end
}

local function set_spy(state)
end

local function called_with(state, arguments)
  local payload = rawget(state, "payload")
  if payload and payload.called_with then
    return state.payload:called_with(arguments)
  else
    error("'called_with' must be chained after 'spy(aspy)'")
  end
end

local function called(state, arguments, compare)
  local num_times = arguments[1]
  if not num_times and not state.mod then
    state.mod = true
    num_times = 0
  end
  local payload = rawget(state, "payload")
  if payload and type(payload) == "table" and payload.called then
    local result, count = state.payload:called(num_times, compare)
    arguments[1] = tostring(num_times or ">0")
    util.tinsert(arguments, 2, tostring(count))
    arguments.n = arguments.n + 1
    arguments.nofmt = arguments.nofmt or {}
    arguments.nofmt[1] = true
    arguments.nofmt[2] = true
    return result
  elseif payload and type(payload) == "function" then
    error("When calling 'spy(aspy)', 'aspy' must not be the original function, but the spy function replacing the original")
  else
    error("'called' must be chained after 'spy(aspy)'")
  end
end

local function called_at_least(state, arguments)
  return called(state, arguments, function(count, expected) return count >= expected end)
end

local function called_at_most(state, arguments)
  return called(state, arguments, function(count, expected) return count <= expected end)
end

local function called_more_than(state, arguments)
  return called(state, arguments, function(count, expected) return count > expected end)
end

local function called_less_than(state, arguments)
  return called(state, arguments, function(count, expected) return count < expected end)
end

assert:register("modifier", "spy", set_spy)
assert:register("assertion", "called_with", called_with, "assertion.called_with.positive", "assertion.called_with.negative")
assert:register("assertion", "called", called, "assertion.called.positive", "assertion.called.negative")
assert:register("assertion", "called_at_least", called_at_least, "assertion.called_at_least.positive", "assertion.called_at_least.negative")
assert:register("assertion", "called_at_most", called_at_most, "assertion.called_at_most.positive", "assertion.called_at_most.negative")
assert:register("assertion", "called_more_than", called_more_than, "assertion.called_more_than.positive", "assertion.called_more_than.negative")
assert:register("assertion", "called_less_than", called_less_than, "assertion.called_less_than.positive", "assertion.called_less_than.negative")

return setmetatable(spy, {
  __call = function(self, ...)
    return spy.new(...)
  end
})
