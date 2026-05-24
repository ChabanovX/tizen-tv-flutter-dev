using System;
using Tizen.Flutter.Embedding;

namespace Runner
{
    public class App : FlutterApplication
    {
        protected override void OnCreate()
        {
            Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: App.OnCreate entered");
            try
            {
                base.OnCreate();
                Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: App.OnCreate after base.OnCreate");
            }
            catch (Exception ex)
            {
                Tizen.Log.Error("ConsoleMessage", $"PHASE3_TRACE: App.OnCreate base threw: {ex}");
                throw;
            }

            try
            {
                GeneratedPluginRegistrant.RegisterPlugins(this);
                Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: App.OnCreate plugins registered");
            }
            catch (Exception ex)
            {
                Tizen.Log.Error("ConsoleMessage", $"PHASE3_TRACE: App.OnCreate RegisterPlugins threw: {ex}");
                throw;
            }
        }

        static void Main(string[] args)
        {
            Tizen.Log.Error("ConsoleMessage", $"PHASE3_TRACE: Main entered argc={args?.Length ?? 0}");
            try
            {
                var app = new App();
                Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: Main after new App, calling Run");
                app.Run(args);
                Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: Main after app.Run returned");
            }
            catch (Exception ex)
            {
                Tizen.Log.Error("ConsoleMessage", $"PHASE3_TRACE: Main caught: {ex}");
                throw;
            }
        }
    }
}
