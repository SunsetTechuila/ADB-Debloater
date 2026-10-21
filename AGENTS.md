Avoid these common mistakes:

- Don't try to define getters and setter for properties. PowerShell classes don't allow that.
- Don't use names `args` and `sender` for parameters in functions. They are reserved names in PowerShell. Use `eventArguments` or `eventSender` instead.
- Don't expect WPF UI to notify View Model when the binded variable changes. PowerShell class properties can't have custom setters, so `OnPropertyChanged` won't be called.

In order to call a base class method from an overridden method, cast `$this` to the base class type: `([BaseClass]$this).BaseMethod()`

Follow The PowerShell Best Practices and Style Guide.
