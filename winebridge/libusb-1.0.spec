# Export table for the Wine libusb-1.0.dll bridge.
# Exactly the functions MegaByte.exe (OpenFK portal reader) P/Invokes.
@ stdcall libusb_init(ptr) wrap_libusb_init
@ stdcall libusb_exit(ptr) wrap_libusb_exit
@ stdcall libusb_open_device_with_vid_pid(ptr long long) wrap_libusb_open_device_with_vid_pid
@ stdcall libusb_close(ptr) wrap_libusb_close
@ stdcall libusb_claim_interface(ptr long) wrap_libusb_claim_interface
@ stdcall libusb_release_interface(ptr long) wrap_libusb_release_interface
@ stdcall libusb_kernel_driver_active(ptr long) wrap_libusb_kernel_driver_active
@ stdcall libusb_detach_kernel_driver(ptr long) wrap_libusb_detach_kernel_driver
@ stdcall libusb_control_transfer(ptr long long long long ptr long long) wrap_libusb_control_transfer
@ stdcall libusb_interrupt_transfer(ptr long ptr long ptr long) wrap_libusb_interrupt_transfer
@ stdcall libusb_error_name(long) wrap_libusb_error_name
