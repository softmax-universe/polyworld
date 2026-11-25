when defined(useMetal4):
  import ../metal/passapi
  export passapi
else:
  import ../native/common
  export common
