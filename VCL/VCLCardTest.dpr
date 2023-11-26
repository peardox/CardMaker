program VCLCardTest;

uses
  Vcl.Forms,
  VCLFormUnit in 'VCLFormUnit.pas' {Form2},
  CardBuilder in '..\Shared\CardBuilder.pas',
  RegisteredFileHandler in '..\Shared\RegisteredFileHandler.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
