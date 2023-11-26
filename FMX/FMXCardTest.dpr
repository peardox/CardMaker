program FMXCardTest;
  {$WARN DUPLICATE_CTOR_DTOR OFF}
//  {$define leakcheck}


uses
  System.StartUpCopy,
  FMX.Forms,
  FMXFormUnit in 'FMXFormUnit.pas' {Form1},
  RegisteredFileHandler in '..\Shared\RegisteredFileHandler.pas',
  CardBuilder in '..\Shared\CardBuilder.pas';

{$R *.res}

begin
{$ifdef leakcheck}
  ReportMemoryLeaksOnShutdown := True;
{$endif}
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
