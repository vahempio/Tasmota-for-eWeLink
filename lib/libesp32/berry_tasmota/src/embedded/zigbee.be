# zigbee code

class zb_device

  def tostring()
    import json
    import string

    var la = self.longaddr      # bytes() of size 8, little-endian
    return string.format("<instance: %s(0x%04X, 0x%08X%08X, name:'%s', model:'%s', manufacturer:'%s')>",
                         classname(self), self.shortaddr,
                         la.get(4,4), la.get(0,4),
                         self.name, self.model, self.manufacturer)
    return 
  end

end