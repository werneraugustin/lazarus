{  $Id$  }
{
 /***************************************************************************
                         sortselectiondlg.pas
                         --------------------


 ***************************************************************************/

 ***************************************************************************
 *                                                                         *
 *   This source is free software; you can redistribute it and/or modify   *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This code is distributed in the hope that it will be useful, but      *
 *   WITHOUT ANY WARRANTY; without even the implied warranty of            *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
 *   General Public License for more details.                              *
 *                                                                         *
 *   A copy of the GNU General Public License is available on the World    *
 *   Wide Web at <http://www.gnu.org/copyleft/gpl.html>. You can also      *
 *   obtain it by writing to the Free Software Foundation,                 *
 *   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.        *
 *                                                                         *
 ***************************************************************************

  Author: Mattias Gaertner
  
  Abstract:
    TSortSelectionDialog is a dialog to setup the parameters for sorting
    text selection.
}
unit SortSelectionDlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, SynEdit, Buttons, StdCtrls, ExtCtrls,
  IDEOptionDefs, Dialogs, BasicCodeTools, AVL_Tree, EditorOptions,
  MiscOptions, SynEditHighlighter;
  
type
  TSortSelDlgState = (ssdPreviewNeedsUpdate, ssdSortedTextNeedsUpdate);
  TSortSelDlgStates = set of TSortSelDlgState;
  
  TSortSelectionDialog = class(TForm)
    PreviewGroupBox: TGroupBox;
    PreviewSynEdit: TSynEdit;
    DirectionRadioGroup: TRadioGroup;
    DomainRadioGroup: TRadioGroup;
    OptionsGroupBox: TGroupBox;
    CaseSensitiveCheckBox: TCheckBox;
    IgnoreSpaceCheckBox: TCheckBox;
    OkButton: TButton;
    CancelButton: TButton;
    procedure CaseSensitiveCheckBoxClick(Sender: TObject);
    procedure DirectionRadioGroupClick(Sender: TObject);
    procedure DomainRadioGroupClick(Sender: TObject);
    procedure IgnoreSpaceCheckBoxClick(Sender: TObject);
    procedure SortSelectionDialogClose(Sender: TObject; var Action: TCloseAction
      );
    procedure SortSelectionDialogResize(Sender: TObject);
  private
    FCaseSensitive: boolean;
    FDirection: TSortDirection;
    FDomain: TSortDomain;
    FIgnoreSpace: boolean;
    FStates: TSortSelDlgStates;
    FTheText: string;
    FUpdateCount: integer;
    FSortedText: string;
    function GetSortedText: string;
    procedure SetCaseSensitive(const AValue: boolean);
    procedure SetDirection(const AValue: TSortDirection);
    procedure SetDomain(const AValue: TSortDomain);
    procedure SetIgnoreSpace(const AValue: boolean);
    procedure SetTheText(const AValue: string);
  public
    constructor Create(TheOwner: TComponent); override;
    procedure BeginUpdate;
    procedure EndUpdate;
    procedure UpdatePreview;
  public
    property CaseSensitive: boolean read FCaseSensitive write SetCaseSensitive;
    property Direction: TSortDirection read FDirection write SetDirection;
    property Domain: TSortDomain read FDomain write SetDomain;
    property IgnoreSpace: boolean read FIgnoreSpace write SetIgnoreSpace;
    property TheText: string read FTheText write SetTheText;
    property SortedText: string read GetSortedText;
  end;
  
function ShowSortSelectionDialog(const TheText: string;
  Highlighter: TSynCustomHighlighter;
  var SortedText: string): TModalResult;
function SortText(const TheText: string; Direction: TSortDirection;
  Domain: TSortDomain; CaseSensitive, IgnoreSpace: boolean): string;

implementation

function ShowSortSelectionDialog(const TheText: string;
  Highlighter: TSynCustomHighlighter;
  var SortedText: string): TModalResult;
var
  SortSelectionDialog: TSortSelectionDialog;
begin
  SortSelectionDialog:=TSortSelectionDialog.Create(Application);
  SortSelectionDialog.TheText:=TheText;
  SortSelectionDialog.PreviewSynEdit.Highlighter:=Highlighter;
  EditorOpts.GetSynEditSelectedColor(SortSelectionDialog.PreviewSynEdit);
  Result:=SortSelectionDialog.ShowModal;
  if Result=mrOk then
    SortedText:=SortSelectionDialog.SortedText;
  IDEDialogLayoutList.SaveLayout(SortSelectionDialog);
  SortSelectionDialog.Free;
end;

type
  TTextBlockCompareSettings = class
  public
    CaseSensitive: boolean;
    IgnoreSpace: boolean;
    Ascending: boolean;
  end;

  TTextBlock = class
  public
    Settings: TTextBlockCompareSettings;
    Start: PChar;
    Len: integer;
    constructor Create(TheSettings: TTextBlockCompareSettings;
      NewStart: PChar; NewLen: integer);
  end;

{ TTextBlock }

constructor TTextBlock.Create(TheSettings: TTextBlockCompareSettings;
  NewStart: PChar; NewLen: integer);
begin
  Settings:=TheSettings;
  Start:=NewStart;
  Len:=NewLen;
end;
  
function CompareTextBlock(Data1, Data2: Pointer): integer;
var
  Block1: TTextBlock;
  Block2: TTextBlock;
  Settings: TTextBlockCompareSettings;
begin
  Block1:=TTextBlock(Data1);
  Block2:=TTextBlock(Data2);
  Settings:=Block1.Settings;
  Result:=CompareText(Block1.Start,Block1.Len,Block2.Start,Block2.Len,
                      Settings.CaseSensitive,Settings.IgnoreSpace);
  if not Settings.Ascending then
    Result:=-Result;
end;

function SortText(const TheText: string; Direction: TSortDirection;
  Domain: TSortDomain; CaseSensitive, IgnoreSpace: boolean): string;
const
  IdentChars = ['_','a'..'z','A'..'Z'];
  SpaceChars = [' ',#9];
var
  Settings: TTextBlockCompareSettings;
  Tree: TAVLTree;
  StartPos: Integer;
  EndPos: Integer;
  ANode: TAVLTreeNode;
  ABlock: TTextBlock;
  TxtLen: integer;
  LastNode: TAVLTreeNode;
  LastBlock: TTextBlock;
  LastChar: Char;
  Last2Char: Char;
  HeaderIndent: Integer;
  CurIndent: Integer;
  CurPos: Integer;
begin
  Result:=TheText;
  if Result='' then exit;
  // create compare settings
  Settings:=TTextBlockCompareSettings.Create;
  Settings.CaseSensitive:=CaseSensitive;
  Settings.IgnoreSpace:=IgnoreSpace;
  Settings.Ascending:=(Direction=sdAscending);
  // create AVL tree
  Tree:=TAVLTree.Create(@CompareTextBlock);
  
  // collect text blocks
  TxtLen:=length(TheText);
  case Domain of
  
  sdParagraphs:
  begin
    // paragraphs:
    //   A paragraph is here a header line and all the lines to the next header
    //   line. A header line has the same indent as the first selected line.

    // find indent in first line
    HeaderIndent:=0;
    while (HeaderIndent<TxtLen) and (TheText[HeaderIndent+1] in SpaceChars) do
      inc(HeaderIndent);

    // split text into blocks
    StartPos:=1;
    EndPos:=StartPos;
    while EndPos<=TxtLen do begin
      CurPos:=EndPos;
      // find indent of current line
      while (CurPos<=TxtLen) and (TheText[CurPos] in SpaceChars) do
        inc(CurPos);
      CurIndent:=CurPos-EndPos;
      if CurIndent=HeaderIndent then begin
        // new block
        if EndPos>StartPos then
          Tree.Add(
            TTextBlock.Create(Settings,@TheText[StartPos],EndPos-StartPos));
        StartPos:=EndPos;
      end;
      EndPos:=CurPos;
      // add line to block
      // read line
      while (EndPos<=TxtLen) and (not (TheText[EndPos] in [#10,#13])) do
        inc(EndPos);
      // read line end
      if (EndPos<=TxtLen) then begin
        inc(EndPos);
        if (EndPos<=TxtLen) and (TheText[EndPos] in [#10,#13])
        and (TheText[EndPos]<>TheText[EndPos-1]) then
          inc(EndPos);
      end;
    end;
    if EndPos>StartPos then
      Tree.Add(TTextBlock.Create(Settings,@TheText[StartPos],EndPos-StartPos));
  end;
  
  sdWords, sdLines:
  begin
    StartPos:=1;
    while StartPos<=TxtLen do begin
      EndPos:=StartPos+1;
      while (EndPos<=TxtLen) do begin
        case Domain of
        sdWords:
          // check if word start
          if (TheText[EndPos] in IdentChars)
          and (EndPos>1)
          and (not (TheText[EndPos-1] in IdentChars))
          then
            break;

        sdLines:
          // check if LineEnd
          if (TheText[EndPos] in [#10,#13]) then begin
            inc(EndPos);
            if (EndPos<=TxtLen) and (TheText[EndPos] in [#10,#13])
            and (TheText[EndPos]<>TheText[EndPos-1]) then
              inc(EndPos);
            break;
          end;

        end;
        inc(EndPos);
      end;
      if EndPos>TxtLen then EndPos:=TxtLen+1;
      if EndPos>StartPos then
        Tree.Add(TTextBlock.Create(Settings,@TheText[StartPos],EndPos-StartPos));
      StartPos:=EndPos;
    end;
  end;
  
  else
    writeln('ERROR: Domain not implemented');
  end;
  
  // build sorted text
  Result:='';
  ANode:=Tree.FindHighest;
  while ANode<>nil do begin
    ABlock:=TTextBlock(ANode.Data);
    Result:=Result+copy(TheText,ABlock.Start-PChar(TheText)+1,ABlock.Len);
    case Domain of
    sdLines,sdParagraphs:
      if not (Result[length(Result)] in [#10,#13]) then begin
        // this was the last line before the sorting
        // if it moved, then copy the line end of the new last line
        LastNode:=Tree.FindLowest;
        LastBlock:=TTextBlock(LastNode.Data);
        LastChar:=PChar(LastBlock.Start+LastBlock.Len-1)^;
        if LastChar in [#10,#13] then begin
          if (LastBlock.Len>1) then begin
            Last2Char:=PChar(LastBlock.Start+LastBlock.Len-2)^;
            if Last2Char in [#10,#13] then
              Result:=Result+Last2Char;
          end;
          Result:=Result+LastChar;
        end;

      end;
    end;
    ANode:=Tree.FindPrecessor(ANode);
  end;
  
  // clean up
  Tree.FreeAndClear;
  Settings.Free;
end;

{ TSortSelectionDialog }

procedure TSortSelectionDialog.SortSelectionDialogResize(Sender: TObject);
begin
  with PreviewGroupBox do begin
    Width:=Self.ClientWidth-2*Left;
    Height:=Self.ClientHeight-Top-90;
  end;

  with DirectionRadioGroup do begin
    Top:=PreviewGroupBox.Top+PreviewGroupBox.Height+5;
    Width:=((Self.ClientWidth-5) div 2)-Left;
  end;

  with DomainRadioGroup do begin
    Left:=DirectionRadioGroup.Left+DirectionRadioGroup.Width+5;
    Top:=DirectionRadioGroup.Top;
    Width:=DirectionRadioGroup.Width;
    Height:=DirectionRadioGroup.Height;
  end;

  with OkButton do begin
    Left:=Self.ClientWidth-200;
    Top:=Self.ClientHeight-35;
  end;

  with CancelButton do begin
    Left:=Self.ClientWidth-100;
    Top:=OkButton.Top;
  end;
end;

procedure TSortSelectionDialog.DirectionRadioGroupClick(Sender: TObject);
begin
  if DirectionRadioGroup.ItemIndex=0 then
    Direction:=sdAscending
  else
    Direction:=sdDescending;
end;

procedure TSortSelectionDialog.CaseSensitiveCheckBoxClick(Sender: TObject);
begin
  CaseSensitive:=CaseSensitiveCheckBox.Checked;
end;

procedure TSortSelectionDialog.DomainRadioGroupClick(Sender: TObject);
begin
  case DomainRadioGroup.ItemIndex of
  0: Domain:=sdLines;
  1: Domain:=sdWords;
  2: Domain:=sdParagraphs;
  else
    Domain:=sdLines;
  end;
end;

procedure TSortSelectionDialog.IgnoreSpaceCheckBoxClick(Sender: TObject);
begin
  IgnoreSpace:=IgnoreSpaceCheckBox.Checked;
end;

procedure TSortSelectionDialog.SortSelectionDialogClose(Sender: TObject;
  var Action: TCloseAction);
begin
  MiscellaneousOptions.SortSelDirection:=Direction;
  MiscellaneousOptions.SortSelDomain:=Domain;
end;

procedure TSortSelectionDialog.SetDirection(const AValue: TSortDirection);
begin
  if FDirection=AValue then exit;
  FDirection:=AValue;
  FStates:=FStates+[ssdPreviewNeedsUpdate,ssdSortedTextNeedsUpdate];
  UpdatePreview;
end;

function TSortSelectionDialog.GetSortedText: string;
begin
  if ssdSortedTextNeedsUpdate in FStates then begin
    FSortedText:=SortText(TheText,Direction,Domain,CaseSensitive,IgnoreSpace);
    Exclude(FStates,ssdSortedTextNeedsUpdate);
  end;
  Result:=FSortedText;
end;

procedure TSortSelectionDialog.SetCaseSensitive(const AValue: boolean);
begin
  if FCaseSensitive=AValue then exit;
  FCaseSensitive:=AValue;
  FStates:=FStates+[ssdPreviewNeedsUpdate,ssdSortedTextNeedsUpdate];
  UpdatePreview;
end;

procedure TSortSelectionDialog.SetDomain(const AValue: TSortDomain);
begin
  if FDomain=AValue then exit;
  FDomain:=AValue;
  FStates:=FStates+[ssdPreviewNeedsUpdate,ssdSortedTextNeedsUpdate];
  UpdatePreview;
end;

procedure TSortSelectionDialog.SetIgnoreSpace(const AValue: boolean);
begin
  if FIgnoreSpace=AValue then exit;
  FIgnoreSpace:=AValue;
  FStates:=FStates+[ssdPreviewNeedsUpdate,ssdSortedTextNeedsUpdate];
  UpdatePreview;
end;

procedure TSortSelectionDialog.SetTheText(const AValue: string);
begin
  if FTheText=AValue then exit;
  FTheText:=AValue;
  FStates:=FStates+[ssdPreviewNeedsUpdate,ssdSortedTextNeedsUpdate];
  UpdatePreview;
end;

constructor TSortSelectionDialog.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  FIgnoreSpace:=true;
  FDirection:=sdAscending;
  FDomain:=sdLines;
  
  Position:=poScreenCenter;
  IDEDialogLayoutList.ApplyLayout(Self,600,400);
  Caption:='Sort Selection';

  PreviewGroupBox:=TGroupBox.Create(Self);
  with PreviewGroupBox do begin
    Name:='PreviewGroupBox';
    Parent:=Self;
    Left:=5;
    Top:=5;
    Width:=Self.ClientWidth-2*Left;
    Height:=Self.ClientHeight-Top-135;
    Caption:='Preview';
  end;

  PreviewSynEdit:=TSynEdit.Create(Self);
  with PreviewSynEdit do begin
    Name:='PreviewSynEdit';
    Parent:=PreviewGroupBox;
    Align:=alClient;
    ReadOnly:=true;
  end;

  DirectionRadioGroup:=TRadioGroup.Create(Self);
  with DirectionRadioGroup do begin
    Name:='DirectionRadioGroup';
    Parent:=Self;
    Left:=5;
    Top:=PreviewGroupBox.Top+PreviewGroupBox.Height+5;
    Width:=((Self.ClientWidth-5) div 2)-Left;
    Height:=40;
    Caption:='Direction';
    with Items do begin
      BeginUpdate;
      Add('Ascending');
      Add('Descending');
      Columns:=2;
      case MiscellaneousOptions.SortSelDirection of
      sdAscending: ItemIndex:=0;
      else         ItemIndex:=1;
      end;
      EndUpdate;
    end;
    OnClick:=@DirectionRadioGroupClick;
  end;
  
  DomainRadioGroup:=TRadioGroup.Create(Self);
  with DomainRadioGroup do begin
    Name:='DomainRadioGroup';
    Parent:=Self;
    Left:=DirectionRadioGroup.Left+DirectionRadioGroup.Width+5;
    Top:=DirectionRadioGroup.Top;
    Width:=DirectionRadioGroup.Width;
    Height:=DirectionRadioGroup.Height;
    Caption:='Domain';
    with Items do begin
      BeginUpdate;
      Add('Lines');
      Add('Words');
      Add('Paragraphs');
      case MiscellaneousOptions.SortSelDomain of
      sdLines: ItemIndex:=0;
      sdWords: ItemIndex:=1;
      else     ItemIndex:=2;
      end;
      Columns:=3;
      EndUpdate;
    end;
    OnClick:=@DomainRadioGroupClick;
  end;
  
  OptionsGroupBox:=TGroupBox.Create(Self);
  with OptionsGroupBox do begin
    Name:='OptionsGroupBox';
    Parent:=Self;
    Left:=DirectionRadioGroup.Left;
    Top:=DirectionRadioGroup.Top+DirectionRadioGroup.Height+5;
    Width:=DirectionRadioGroup.Width;
    Height:=DirectionRadioGroup.Height;
    Caption:='Options';
  end;
  
  CaseSensitiveCheckBox:=TCheckBox.Create(Self);
  with CaseSensitiveCheckBox do begin
    Name:='CaseSensitiveCheckBox';
    Parent:=OptionsGroupBox;
    Left:=2;
    Top:=2;
    Width:=120;
    Caption:='Case Sensitive';
    OnClick:=@CaseSensitiveCheckBoxClick;
  end;

  IgnoreSpaceCheckBox:=TCheckBox.Create(Self);
  with IgnoreSpaceCheckBox do begin
    Name:='IgnoreSpaceCheckBox';
    Parent:=OptionsGroupBox;
    Left:=125;
    Top:=2;
    Width:=120;
    Caption:='Ignore Space';
    Checked:=true;
    OnClick:=@IgnoreSpaceCheckBoxClick;
  end;

  OkButton:=TButton.Create(Self);
  with OkButton do begin
    Name:='OkButton';
    Parent:=Self;
    Left:=Self.ClientWidth-200;
    Top:=Self.ClientHeight-35;
    Caption:='Sort';
    ModalResult:=mrOk;
    Default:=true;
  end;
  
  CancelButton:=TButton.Create(Self);
  with CancelButton do begin
    Name:='CancelButton';
    Parent:=Self;
    Left:=Self.ClientWidth-100;
    Top:=OkButton.Top;
    Caption:='Cancel';
    ModalResult:=mrCancel;
  end;
  
  OnResize:=@SortSelectionDialogResize;
  OnClose:=@SortSelectionDialogClose;
end;

procedure TSortSelectionDialog.BeginUpdate;
begin
  inc(FUpdateCount);
end;

procedure TSortSelectionDialog.EndUpdate;
begin
  dec(FUpdateCount);
  if FUpdateCount=0 then UpdatePreview;
end;

procedure TSortSelectionDialog.UpdatePreview;
begin
  if FUpdateCount>0 then
    Include(FStates,ssdPreviewNeedsUpdate)
  else begin
    Exclude(FStates,ssdPreviewNeedsUpdate);
    PreviewSynEdit.Text:=SortedText;
  end;
end;

end.

