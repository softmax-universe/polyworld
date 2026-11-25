const
  UniformPageBytes* = 64 * 1024
  MaxUniformPages* = 256

proc alignedBytes*(value, alignment: int): int =
  ## Rounds a bounded byte size or cursor to the required native alignment.
  (value + alignment - 1) div alignment * alignment
