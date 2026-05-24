using System;
using Tizen.NUI;

namespace Runner
{
    public class App : NUIApplication
    {
        protected override void OnCreate()
        {
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.OnCreate ENTERED");
            Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: MinimalNUIApp.OnCreate ENTERED");
            base.OnCreate();
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.OnCreate after base");
            Tizen.Log.Error("ConsoleMessage", "PHASE3_TRACE: MinimalNUIApp.OnCreate after base");
        }

        protected override void OnPause()
        {
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.OnPause");
            base.OnPause();
        }

        protected override void OnResume()
        {
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.OnResume");
            base.OnResume();
        }

        protected override void OnTerminate()
        {
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.OnTerminate");
            base.OnTerminate();
        }

        static void Main(string[] args)
        {
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.Main entered");
            var app = new App();
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.Main calling Run");
            app.Run(args);
            Console.Error.WriteLine("PHASE3_STDERR: MinimalNUIApp.Main Run returned");
        }
    }
}
