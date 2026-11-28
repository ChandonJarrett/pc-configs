{ constants, inputs, ... }:
{
  imports = [ inputs.hjem.nixosModules.default ];

  hjem.users.${constants.username} = { };
}
