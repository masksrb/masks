<script>
  import {
    Save,
    ChevronDown,
    X,
    Computer,
    Smartphone,
    Tablet,
    Gamepad,
    Tv,
    Tv2,
    HelpCircle,
    Car,
    Camera,
    Bluetooth,
  } from "lucide-svelte";

  let { device, size } = $props();
  let icon = {
    desktop: Computer,
    smartphone: Smartphone,
    "feature phone": Smartphone,
    tablet: Tablet,
    phablet: Tablet,
    "portable media player": Tablet,
    console: Gamepad,
    tv: Tv,
    "smart display": Tv2,
    "car browser": Car,
    camera: Camera,
    "smart speaker": Bluetooth,
    wearable: Bluetooth,
    peripheral: Bluetooth,
  };

  let Icon = $derived(icon[device.type] || HelpCircle);
</script>

<Icon size={size || 14} />
