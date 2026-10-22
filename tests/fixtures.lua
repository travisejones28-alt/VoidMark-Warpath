-- Standalone static fixture for prospective Lua unit harness.
return {
  legacy = {observations={{zone="duskwood", x=0.5, y=0.5, observedAt=1700000000, source="manual"}}},
  future = {schema=999, observations={}},
  invalid = {zone="redridge", x=2, y=0.5, observedAt=1700000000, source="manual"},
  valid = {zone="redridge", x=0.5, y=0.5, observedAt=1700000000, source="manual"},
}
