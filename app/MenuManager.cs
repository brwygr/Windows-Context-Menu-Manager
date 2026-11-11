using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;
internal static class MenuManager {
 static string root=AppDomain.CurrentDomain.BaseDirectory;
 static void Report(string message) {
  try { string logs=Path.Combine(root,"data","logs"); Directory.CreateDirectory(logs); File.WriteAllText(Path.Combine(logs,"host-error.log"),message); } catch {}
  MessageBox.Show(message,"Windows Context Menu Manager",MessageBoxButtons.OK,MessageBoxIcon.Error);
 }
 [STAThread]
 static void Main() {
  if(!Environment.Is64BitProcess) { Report("This portable package requires 64-bit Windows."); return; }
  string launcher=Path.Combine(root,"Launch.ps1");
  if(!File.Exists(launcher)) { Report("Please extract the complete ZIP before starting MenuManager.exe."); return; }
  try {
   var initial=InitialSessionState.CreateDefault();
   initial.ExecutionPolicy=Microsoft.PowerShell.ExecutionPolicy.Bypass;
   using(var runspace=RunspaceFactory.CreateRunspace(initial)) {
    runspace.ApartmentState=ApartmentState.STA;
    runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;
    runspace.Open();
    using(var shell=PowerShell.Create()) {
     shell.Runspace=runspace;
     shell.AddCommand(launcher);
     shell.Invoke();
     if(shell.HadErrors) { Report(String.Join(Environment.NewLine,shell.Streams.Error)); }
    }
   }
  } catch(Exception error) { Report(error.Message); }
 }
}
