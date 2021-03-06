{
This file is part of the SimpleBOT package.
(c) Luri Darmawan <luri@fastplaz.com>

For the full copyright and license information, please view the LICENSE
file that was distributed with this source code.
}
{
  Default Bot Name : "bot"

  [x] USAGE

  Text := 'hi, apa kabar';
  .
  .
  SimpleBOT := TSimpleBotModule.Create;
  SimpleBOT.OnError := @OnErrorHandler;  // Your Custom Message
  SimpleBOT.Handler['your_defined_action'] := @yourDefinedActionHandler;
  TextResponse := SimpleBOT.Exec(Text);
  .
  .
  SimpleBOT.Free;


}
unit simplebot_controller;

{$mode objfpc}{$H+}

{$ifdef AI_REDIS}
{$else}
{$endif}

interface

uses
  {$ifdef AI_REDIS}
  simpleairedis_controller,
  {$else}
  simpleai_controller,
  {$endif}
  suggestion_controller, domainwhois_controller,
  resiibacor_integration,
  kamus_controller,
  fastplaz_handler, logutil_lib, http_lib,
  fpexprpars, // formula
  dateutils, IniFiles,
  RegExpr, fgl, fpjson, Classes, SysUtils, fpcgi, HTTPDefs;

const
  _AI_BOTNAME_DEFAULT = 'bot';
  _AI_CONFIG_NAME = 'ai/default/name';

type

  generic TStringHashMap<T> = class(specialize TFPGMap<String,T>) end;
  THandlerCallback = function(const IntentName: string;
    Params: TStrings): string of object;
  THandlerCallbackMap = specialize TStringHashMap<THandlerCallback>;

  TOnErrorCallback = function(const Text: string): string of object;

  TStorageType = (stFile, stDatabase);

  { TSimpleBotModule }

  TSimpleBotModule = class
  private
    FAskName: boolean;
    FBotName: string;
    FCLI: Boolean;
    FFirstSessionResponse: boolean;
    FIsExternal: Boolean;
    FLastVisit: Cardinal;
    FSecondSessionResponse: boolean;
    FSessionUserID: string;
    FStorageFileName: string;
    FStorageType: TStorageType;
    FUserData: TIniFile;
    Suggestion: TBotSuggestion;
    FAskCountdown: integer;
    FAskEmail: boolean;
    FChatID: string;
    FisAnswered: boolean;
    FOnError: TOnErrorCallback;
    FDataLoaded: boolean;
    Text: string;
    FIsStemming : boolean;
    function getAdditionalParameters: TStrings;
    function getDebug: boolean;
    function getHandler(const TagName: string): THandlerCallback;
    function getIsStemming: boolean;
    function getLastSeen: Cardinal;
    function getOriginalMessage: string;
    function getResponseText: TStringList;
    function getStandardWordCheck: Boolean;
    function getTrimMessage: boolean;
    function getUserData(const KeyName: string): string;

    procedure LoadAIDataFromFile;
    procedure setDebug(AValue: boolean);
    procedure setHandler(const TagName: string; AValue: THandlerCallback);
    function handlerProcessing(ActionName, Message: string): string;
    function defineHandlerDefault(): string;
    function mathHandlerDefault(): string;
    function ErrorHandler(Message: string): string;
    procedure setIsStemming(AValue: boolean);
    procedure setOriginalMessage(AValue: string);
    procedure setStandardWordCheck(AValue: Boolean);
    procedure setStorageType(AValue: TStorageType);
    procedure setTrimMessage(AValue: boolean);
    procedure setUserData(const KeyName: string; AValue: string);
    function URL_Handler(const IntentName: string; Params: TStrings): string;
    function domainWhoisHandler(const IntentName: string; Params: TStrings): string;
    function kamusHandler(const IntentName: string; Params: TStrings): string;
    function prepareQuestion: boolean;
    function echoQuestions(IntentName: string; Key: string = ''): string;

    // example handler
    function Example_Handler(const IntentName: string; Params: TStrings): string;

    function isAnswerOld(): boolean;
    function isMentioned: boolean;
  public
    {$ifdef AI_REDIS}
    SimpleAI: TSimpleAIRedis;
    {$else}
    SimpleAI: TSimpleAI;
    {$endif}
    constructor Create; virtual;
    destructor Destroy; virtual;
    procedure LoadConfig(DataName: string);

    function Exec(Message: string): string;
    function GetResponse(IntentName: string; Action: string = '';
      EntitiesKey: string = ''): string;
    function StringReplacement(Message: string; ForceWithSpace: boolean = True): string;
    procedure ClearQuestions;
    procedure SetQuestions(IntentName: string;
      MsgCount: integer = _AI_COUNT__MINIMAL_ASKNAME);
    procedure Answered;

    function isFormula: boolean;
    function Formula( AText: string): string;
    procedure SetSession(Key, Value: string);
    function GetSession(Key: string): string;
    function IterationHandler(const ActionName:String; const AMessage: String): String;

    property BotName: string read FBotName write FBotName;
    property ChatID: string read FChatID write FChatID;
    property AskCountdown: integer read FAskCountdown;
    property FirstSessionResponse: boolean read FFirstSessionResponse
      write FFirstSessionResponse;
    property SecondSessionResponse: boolean
      read FSecondSessionResponse write FSecondSessionResponse;

    property Debug: boolean read getDebug write setDebug;
    property isDataLoaded: boolean read FDataLoaded;
    property isAnswer: boolean read FisAnswered;
    property AskName: boolean read FAskName write FAskName;
    property AskEmail: boolean read FAskEmail write FAskEmail;
    procedure TelegramSend(Token, ChatIDRef, ReplyToMessageID, Message: string);

    property UserData[const KeyName: string]: string read getUserData write setUserData;
    property Handler[const TagName: string]: THandlerCallback
      read getHandler write setHandler;
    property OnError: TOnErrorCallback read FOnError write FOnError;
    property TrimMessage: boolean read getTrimMessage write setTrimMessage;

    property SessionUserID:string read FSessionUserID write FSessionUserID;
  published
    property CLI:Boolean read FCLI write FCLI;
    property StorageType:TStorageType read FStorageType write setStorageType;
    property StorageFileName:string read FStorageFileName write FStorageFileName;
    property LastVisit:Cardinal read FLastVisit;
    property LastSeen:Cardinal read getLastSeen; // in seconds
    property OriginalMessage: string read getOriginalMessage write setOriginalMessage;
    property AdditionalParameters: TStrings read getAdditionalParameters;
    property ResponseText: TStringList read getResponseText;
    property IsExternal: Boolean read FIsExternal;

    // Stemming
    property IsStemming: boolean read getIsStemming write setIsStemming;
    property StandardWordCheck: Boolean read getStandardWordCheck write setStandardWordCheck;
  end;

var
  ___HandlerCallbackMap: THandlerCallbackMap;

implementation

uses
  json_lib, common;

const
  REGEX_EQUATION =
    '^[cos|sin|tan|tangen|sqr|sqrt|log|ln|sec|cosec|arctan|abs|exp|frac|int|round|trunc|shl|shr|ifs|iff|ifd|ifi|0-9*+ ().,-/:]+$';

  _AI_CONFIG_BASEDIR = 'ai/default/basedir';
  _AI_CONFIG_ENTITIES = 'ai/default/entities';
  _AI_CONFIG_INTENTS = 'ai/default/intents';
  _AI_CONFIG_RESPONSE = 'ai/default/response';
  _AI_CONFIG_DEBUG = 'ai/default/debug';
  _AI_CONFIG_DATASOURCE = 'ai/default/datasource';

  _AI_DATASOURCE_REDIS = 'redis';
  _AI_DATASOURCE_FILE = 'file';
  _AI_RESPONSE_INTRODUCTION = 'introduction';
  _AI_RESPONSE_FIRSTSESSION = 'firstsession';
  _AI_RESPONSE_ABOUTME = 'aboutme';
  _AI_RESPONSE_SECONDSESSION = 'secondsession';

  _AL_LOG_LEARN = 'learn';
  _AI_SESSION_VISITED = 'AI_VISITED';
  _AI_SESSION_LASTVISIT = 'AI_VISITLAST';
  _AI_SESSION_LASTACTION = 'AI_ACTIONLAST';
  _AI_SESSION_MESSAGECOUNT = 'AI_MESSAGECOUNT';
  //_AI_MESSAGEWAITINGLIMIT = 'AI_MESSAGEWAITINGLIMIT';

  _AI_SESSION_ASK_INTENT = 'AI_ASK_INTENT';
  _AI_SESSION_ASK_KEY = 'AI_ASK_KEY';
  _AI_SESSION_ASK_VAR = 'AI_ASK_VAR';
  _AI_SESSION_ASK_COUNTDOWN = 'AI_ASK_COUNTDOWN';
  _AI_ASK_NAME = 'TanyaNama';
  _AI_ASK_EMAIL = 'TanyaEmail';
  _AI_ASK_COUNTDOWN = 'askCount';

  _AI_DEFINE = 'define';
  _AI_MATH = 'math';
  _AI_SESSION_USER = 'AI_USER_';
  //_AI_VARKEY = 'varkey';
  _AI_OBJECT = 'OBJECT';
  _AI_OBJECT_DATE = 'OBJECT_DATE';
  _AI_CONTEXT = 'CONTEXT';
  _AI_CONTEXT_ACTION = 'CONTEXT_ACTION';
  _AI_CONTEXT_DATE = 'CONTEXT_DATE';
  _AI_CONTEXT_PARAM = 'CONTEXT_PARAM';

  CONTEXT_DISCUSSION_MAXTIME = 30; //30 minutes

  _TELEGRAM_API_URL = 'https://api.telegram.org/bot';
  //_TELEGRAM_CONFIG_TOKEN = 'telegram/token';

constructor TSimpleBotModule.Create;
begin
  FCLI := FALSE;
  FOnError := nil;
  ___HandlerCallbackMap := THandlerCallbackMap.Create;

  FDataLoaded := False;
  FStorageType := stFile;
  FStorageFileName := '';
  {$ifdef AI_REDIS}
  SimpleAI := TSimpleAIRedis.Create;
  {$else}
  SimpleAI := TSimpleAI.Create;
  {$endif}
  LoadConfig('');
  FBotName := _AI_BOTNAME_DEFAULT;
  Suggestion := TBotSuggestion.Create;
  Suggestion.FileName := Config[_AI_CONFIG_BASEDIR] + 'suggestion.txt';

  FIsExternal := False;
  FIsStemming := False;
  FChatID := '';
  FAskCountdown := 0;
  FAskName := False;
  FAskEmail := False;
  FSecondSessionResponse := False;
  FFirstSessionResponse := False;
  FSessionUserID := '';
  FLastVisit := 0;
  Handler['example'] := @Example_Handler;
  Handler['url'] := @URL_Handler;
  Handler['suggestion'] := @Suggestion.SuggestionHandler;
  Handler['domain_whois'] := @domainWhoisHandler;
  Handler['kamus'] := @kamusHandler;
end;

destructor TSimpleBotModule.Destroy;
begin
  Suggestion.Free;
  ___HandlerCallbackMap.Free;
  if Assigned(SimpleAI) then
    SimpleAI.Free;
end;

procedure TSimpleBotModule.LoadConfig(DataName: string);
var
  s: String;
begin

  try
    SimpleAI.Debug := Config[_AI_CONFIG_DEBUG];
    SimpleAI.AIName := Config[_AI_CONFIG_NAME];
  except
  end;

  // redis
  {$ifdef AI_REDIS}
  SimpleAI.UseRedis := False;
  s := Config[_AI_CONFIG_DATASOURCE];
  if s = _AI_DATASOURCE_REDIS then
  begin
    SimpleAI.UseRedis := True;
    if SimpleAI.LoadDataFromRedis then
      Exit;
  end;
  {$endif}

  //-- sementar buat test
  LoadAIDataFromFile;

end;

procedure TSimpleBotModule.LoadAIDataFromFile;
var
  i: integer;
  s, basedir: string;
  jData: TJSONData;
begin
  basedir := Config[_AI_CONFIG_BASEDIR];

  // load Entities
  s := Config[_AI_CONFIG_ENTITIES];
  jData := GetJSON(s);
  if jData.Count > 0 then
    for i := 0 to jData.Count - 1 do
    begin
      SimpleAI.AddEntitiesFromFile(basedir + jData.Items[i].AsString);
    end;

  jData.Free;

  // load Intents
  s := Config[_AI_CONFIG_INTENTS];
  jData := GetJSON(s);
  if jData.Count > 0 then
    for i := 0 to jData.Count - 1 do
    begin
      SimpleAI.AddIntentFromFile(basedir + jData.Items[i].AsString);
    end;
  jData.Free;

  // load Response
  s := Config[_AI_CONFIG_RESPONSE];
  jData := GetJSON(s);
  if jData.Count > 0 then
    for i := 0 to jData.Count - 1 do
    begin
      SimpleAI.AddResponFromFile(basedir + jData.Items[i].AsString);
    end;
  jData.Free;

  FDataLoaded := True;
end;

procedure TSimpleBotModule.setDebug(AValue: boolean);
begin
  SimpleAI.Debug := AValue;
end;

function TSimpleBotModule.getDebug: boolean;
begin
  Result := SimpleAI.Debug;
end;

function TSimpleBotModule.getAdditionalParameters: TStrings;
begin
  Result := SimpleAI.AdditionalParameters;
end;

procedure TSimpleBotModule.setHandler(const TagName: string; AValue: THandlerCallback);
begin
  ___HandlerCallbackMap[TagName] := AValue;
end;

function TSimpleBotModule.getHandler(const TagName: string): THandlerCallback;
begin
  Result := ___HandlerCallbackMap[TagName];
end;

function TSimpleBotModule.getTrimMessage: boolean;
begin
  Result := SimpleAI.TrimMessage;
end;

procedure TSimpleBotModule.setUserData(const KeyName: string; AValue: string);
begin
  SetSession( FSessionUserID + '_' + _AI_SESSION_USER + KeyName, AValue);

  if (FStorageType = stFile)and(FStorageFileName<>'') then
  begin
    try
      FUserData := TIniFile.Create( FStorageFileName);
      FUserData.WriteString( FSessionUserID, KeyName, AValue);
    except
      on E:Exception do
      begin
        if Debug then
          LogUtil.Add( E.Message, 'USERDATA');
      end;
    end;
    FUserData.Free;
  end;
end;

function TSimpleBotModule.getUserData(const KeyName: string): string;
begin
  Result := GetSession( FSessionUserID + '_' + _AI_SESSION_USER + KeyName);

  if (FStorageType = stFile)and(FStorageFileName<>'') then
  begin
    try
      FUserData := TIniFile.Create( FStorageFileName);
      Result := FUserData.ReadString( FSessionUserID, KeyName, '');
    except
    end;
    FUserData.Free;
  end;
end;

function TSimpleBotModule.handlerProcessing(ActionName, Message: string): string;
var
  i: integer;
  h: THandlerCallback;
begin
  Result := ''; //SimpleAI.ResponseText.Text;
  i := ___HandlerCallbackMap.IndexOf(ActionName);
  if i = -1 then
    Exit;
  h := ___HandlerCallbackMap.Data[i];
  Result := h(SimpleAI.IntentName, SimpleAI.Parameters);
end;

function TSimpleBotModule.defineHandlerDefault(): string; // for name & email
var
  s, keyName, keyValue: string;
  lst: TStrings;
begin
  Result := '';
  keyName := 'Key';
  keyValue := SimpleAI.Parameters.Values['Key_value'];

  // Email
  if SimpleAI.Parameters.IndexOfName('Email') <> -1 then
  begin
    keyName := 'Email';
    keyValue := SimpleAI.Parameters.Values['Email'];
    if not isEmail(keyValue) then
    begin
      Result := SimpleAI.GetResponse('EmailTidakValid');
      Exit;
    end;
    UserData['Email'] := keyValue;
    Answered;
    s := UserData['Name'];
    if s = '' then
      SetQuestions(_AI_ASK_NAME);
  end;

  if SimpleAI.Parameters.IndexOfName('Name') <> -1 then
  begin
    keyName := 'Name';
    keyValue := SimpleAI.Parameters.Values['Name'];
    lst := Explode(keyValue, ' ');
    if lst.Count > 2 then
    begin
      lst.Free;
      Exit;
    end
    else
    begin
      UserData['Name'] := keyValue;
      SetQuestions('');
      if FAskEmail then
      begin
        s := UserData['Email'];
        if s = '' then
        begin
          SetQuestions(_AI_ASK_EMAIL);
        end;
      end;
    end;
    lst.Free;
  end;

  Result := GetResponse(SimpleAI.IntentName + 'Response', '', '');
  if preg_match('%(' + keyName + ')%', Result) then
  begin
    Result := preg_replace('%(' + keyName + ')%', keyValue, Result, True);
  end;

  Result := StringReplacement(Result);
end;

function TSimpleBotModule.mathHandlerDefault(): string;
var
  mathParser: TFPExpressionParser;
  resultValue: double;
const
  AllowedOperator = ['+', '-', '/', '*', '^'];
begin
  Result := SimpleAI.Parameters.Values['Formula_value'];
  Result := StringReplace(Result, ':', '/', [rfReplaceAll]);
  Result := StringReplace(Result, 'x', '*', [rfReplaceAll]);
  Result := StringReplace(Result, 'dibagi', '/', [rfReplaceAll]);
  Result := StringReplace(Result, 'bagi', '/', [rfReplaceAll]);
  Result := StringReplace(Result, 'dikali', '*', [rfReplaceAll]);
  Result := StringReplace(Result, 'kali', '*', [rfReplaceAll]);
  Result := StringReplace(Result, 'ditambah', '+', [rfReplaceAll]);
  Result := StringReplace(Result, 'tambah', '+', [rfReplaceAll]);
  Result := StringReplace(Result, 'dikurangi', '-', [rfReplaceAll]);
  Result := StringReplace(Result, 'dikurang', '-', [rfReplaceAll]);
  Result := StringReplace(Result, 'koma', '.', [rfReplaceAll]);
  Result := StringReplace(Result, 'rp.', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'rp', '', [rfReplaceAll]);
  Result := StringReplace(Result, '=', '', [rfReplaceAll]);
  Result := StringReplace(Result, '?', '', [rfReplaceAll]);
  Result := StringReplace(Result, 'nol', '0', [rfReplaceAll]);
  Result := Result.Replace('sama dengan', '');
  Result := Result.Replace('berapa', '');
  Result := Result.Trim;
  if Result[1] = ',' then
    Result := Copy(Result, 2);
  if Result[1] = '.' then
    Result := Copy(Result, 2);
  Result := Result.Trim;
  Result := StringHumanToNominal(Result);
  Result := Result.Replace(' ' , '');
  if (Result[1] in AllowedOperator) then
  begin
    if UserData['math_result'].IsEmpty then
    begin
      Result := '..... :( ';
      Exit;
    end;
    Result := UserData['math_result'] + Result;
  end;
  Result := '(' + Result + ')';
  if not preg_match(REGEX_EQUATION, Result) then
  begin
    Result := '..... :( ';
    Exit;
  end;

  mathParser := TFPExpressionParser.Create(nil);
  try
    mathParser.BuiltIns := [bcMath, bcBoolean];
    mathParser.Expression := Result;
    resultValue := ArgToFloat(mathParser.Evaluate);
    UserData['math_result'] := f2s(resultValue);
    ThousandSeparator:='.';
    DecimalSeparator:=',';
    Result := FloatToStr(resultValue);
    Result := Format('%5.2N',[resultValue]);
    Result := Result.Replace(',00','');
  except
  end;
  mathParser.Free;
end;

function TSimpleBotModule.ErrorHandler(Message: string): string;
var
  d1: TDateTime;
begin
  Result := '';
  LogUtil.Add(Message, _AL_LOG_LEARN);

  if isFormula then
  begin
    SimpleAI.Parameters.Values['Formula_value'] := Text;
    Result := mathHandlerDefault();
    Exit;
  end;

  if UserData[_AI_OBJECT] <> '' then
  begin
    try
      d1 := StrToDateTime(UserData[_AI_OBJECT_DATE]);
      if MinutesBetween(d1, now) < 10 then
      begin
        Result := GetResponse('nonewithobject');
        Exit;
      end;
    except
    end;
  end;
  Result := GetResponse('none');

  if isWord(Message) then
  begin
    if isEmail(Message) then
    begin
      UserData['Email'] := Message;
      Result := 'Data email telah kami simpan';
    end;
  end;
end;

function TSimpleBotModule.getIsStemming: boolean;
begin
  Result := FIsStemming;
end;

function TSimpleBotModule.getLastSeen: Cardinal;
var
  s: string;
begin
  Result := 0;
  //Result := (_GetTickCount - FLastVisit) div 3600000; // jam
  Result := (_GetTickCount - FLastVisit) div 1000;
end;

function TSimpleBotModule.getOriginalMessage: string;
begin
  Result := SimpleAI.OriginalMessage;
end;

function TSimpleBotModule.getResponseText: TStringList;
begin
  Result := SimpleAI.ResponseText;
end;

function TSimpleBotModule.getStandardWordCheck: Boolean;
begin
  Result := SimpleAI.StandardWordCheck;
end;

procedure TSimpleBotModule.setIsStemming(AValue: boolean);
begin
    FIsStemming := AValue;
end;

procedure TSimpleBotModule.setOriginalMessage(AValue: string);
begin
  SimpleAI.OriginalMessage := AValue;
end;

procedure TSimpleBotModule.setStandardWordCheck(AValue: Boolean);
begin
  SimpleAI.StandardWordCheck := AValue;
end;

procedure TSimpleBotModule.setStorageType(AValue: TStorageType);
begin
  if FStorageType=AValue then Exit;
  FStorageType:=AValue;

  if FStorageType = stFile then
  begin

  end;
end;

procedure TSimpleBotModule.setTrimMessage(AValue: boolean);
begin
  SimpleAI.TrimMessage := AValue;
end;

function TSimpleBotModule.URL_Handler(const IntentName: string;
  Params: TStrings): string;
var
  i: integer;
  lst: TStrings;
  s, url, method, parameters: string;
  httpClient: THTTPLib;
  httpResponse: IHTTPResponse;
begin
  Result := '';
  lst := Explode(SimpleAI.Action, _AI_ACTION_SEPARATOR);
  if lst.Count = 1 then
    Exit;

  method := 'get';
  if lst.Count = 2 then
    url := lst[1]
  else
  begin
    method := lst[1];
    url := lst[2];
  end;

  if pos('?', url) = 0 then
    url := url + '?';

  httpClient := THTTPLib.Create;
  parameters := '';
  for i := 0 to SimpleAI.Parameters.Count - 1 do
  begin
    if method = 'get' then
    begin
      if i <= SimpleAI.Parameters.Count - 1 then
        parameters := parameters + '&';
      parameters := parameters + SimpleAI.Parameters.Names[i] + '=' +
        SimpleAI.Parameters.ValueFromIndex[i];
    end;
    if method = 'post' then
    begin
      s := SimpleAI.Parameters.Names[i];
      httpClient.FormData[s] := SimpleAI.Parameters.ValueFromIndex[i];
    end;
  end;

  httpClient.FormData['var1'] := 'value1';
  httpClient.URL := url + parameters;

  if method = 'get' then
    httpResponse := httpClient.Get();
  if method = 'post' then
    httpResponse := httpClient.Post();

  if httpResponse.ResultCode = 200 then
    Result := httpResponse.ResultText;

  httpClient.Free;
end;

function TSimpleBotModule.domainWhoisHandler(const IntentName: string;
  Params: TStrings): string;
var
  domain : string;
  domainWhois: TDomainWhoisController;
begin
  Result := '..';
  domain := Params.Values['domain_value'];
  domain := preg_replace('<(.*)\|(.*)>', '$2', domain); // striptag slack: "whois <http://domain.com|domain.com>"

  domainWhois := TDomainWhoisController.Create;
  Result := domainWhois.Find(domain, Params.Values['option_value']);
  domainWhois.Free;
end;

function TSimpleBotModule.kamusHandler(const IntentName: string;
  Params: TStrings): string;
var
  kamus: TKamusController;
  s: string;
begin
  Result := '...';
  try
    kamus := TKamusController.Create;
    kamus.Token := Config['ibacor/default/token'];
    s := Params.Values['Text_value'];
    if Params.Values['word_value'] <> '' then
      Result := kamus.Find(Params.Values['word_value'])
    else
      Result := kamus.Find( s);
  except
  end;
  kamus.Free;
end;

procedure TSimpleBotModule.SetSession(Key, Value: string);
var
  sessionKey: string;
begin
  sessionKey := ChatID + '_' + Key;
  _SESSION[sessionKey] := Value;
end;

function TSimpleBotModule.GetSession(Key: string): string;
var
  sessionKey: string;
begin
  sessionKey := ChatID + '_' + Key;
  Result := _SESSION[sessionKey];
end;

function TSimpleBotModule.IterationHandler(const ActionName: String;
  const AMessage: String): String;
begin
  Result := handlerProcessing(ActionName, AMessage);
end;

function TSimpleBotModule.Example_Handler(const IntentName: string;
  Params: TStrings): string;
begin
  Result := '';
  if not SimpleAI.Debug then
    Exit;
  Result := 'This is Example Hook Handler';
end;

function TSimpleBotModule.Exec(Message: string): string;
var
  json: TJSONUtil;
  messageCount: integer;
  s, text_response, askIntent: string;
  lst: TStrings;
  context_params: TStringList;

  lastvisit_time, lastvisit_length: cardinal;
begin
  FIsExternal := False;
  if not CLI then
  begin
    if _GET['_DEBUG'] <> '' then
      SimpleAI.Debug := True;
  end;

  if Message = '' then
  begin
    Result := '{}';
    Exit;
  end;

  FisAnswered := False;
  Text := LowerCase(Message);
  text_response := '';
  SimpleAI.PrefixText := '';
  SimpleAI.SuffixText := '';

  // is firsttime ?
  s := getSession(_AI_SESSION_VISITED);
  if s = '' then
  begin
    if FFirstSessionResponse then
    begin
      s := SimpleAI.GetResponse(_AI_RESPONSE_INTRODUCTION, '',
        _AI_RESPONSE_FIRSTSESSION);
      s := s + SimpleAI.GetResponse(_AI_RESPONSE_INTRODUCTION, '',
        _AI_RESPONSE_ABOUTME);
      SimpleAI.SuffixText := s;
    end;

    //SimpleAI.ResponseText.Add(s);
    setSession(_AI_SESSION_VISITED, '1');
    setSession(_AI_SESSION_LASTVISIT, i2s(_GetTickCount));
    UserData[_AI_SESSION_LASTVISIT] := i2s(_GetTickCount);
    if FAskName then
      if UserData['Name'] = '' then
        SetQuestions(_AI_ASK_NAME);
  end;

  //s := getSession(_AI_SESSION_LASTVISIT);
  s := UserData[_AI_SESSION_LASTVISIT];
  try
    lastvisit_time := _GetTickCount;
    lastvisit_time := StrToInt64(s);
    FLastVisit := lastvisit_time;
  except
  end;
  lastvisit_length := (_GetTickCount - lastvisit_time) div 3600000; // jam
  if lastvisit_length > 1 then
  begin
    if FSecondSessionResponse then
    begin
      s := SimpleAI.GetResponse(_AI_RESPONSE_INTRODUCTION, '',
        _AI_RESPONSE_SECONDSESSION);
      s := StringReplacement(s);
      if s <> '' then
        SimpleAI.ResponseText.Add(s);
    end;
    setSession(_AI_SESSION_MESSAGECOUNT, '0');
    UserData[_AI_OBJECT] := '';
    UserData[_AI_OBJECT_DATE] := '';
  end;

  // message count
  try
    messageCount := 0;
    messageCount := s2i(getSession(_AI_SESSION_MESSAGECOUNT));
  except
  end;
  messageCount := messageCount + 1;

  SimpleAI.Stemming := FIsStemming;
  if SimpleAI.Exec(Text) then
  begin
    FIsExternal := SimpleAI.IsExternal;
    SimpleAI.ResponseText.Text := trim(SimpleAI.ResponseText.Text);
    text_response := SimpleAI.ResponseText.Text;

    if SimpleAI.Action <> '' then
    begin
      // do action
      setSession(_AI_SESSION_LASTACTION, SimpleAI.Action);
      text_response := '';
      lst := Explode(SimpleAI.Action, _AI_ACTION_SEPARATOR);

      if lst[0] = 'define' then
      begin
        text_response := defineHandlerDefault();
      end;

      if lst[0] = _AI_MATH then
      begin
        text_response := mathHandlerDefault();
      end;

      text_response := text_response + handlerProcessing(lst[0], Message);
      lst.Free;

      if text_response <> '' then
        SimpleAI.ResponseText.add(text_response);
    end; //SimpleAI.Action;

    if SimpleAI.SimpleAILib.Intent.ObjectName <> '' then
    begin
      UserData[_AI_OBJECT] := SimpleAI.SimpleAILib.Intent.ObjectName;
      UserData[_AI_OBJECT_DATE] := DateTimeToStr(Now);
    end;
    if SimpleAI.SimpleAILib.Intent.Context <> '' then
    begin
      context_params := TStringList.Create;
      context_params.Text := SimpleAI.SimpleAILib.Intent.Parameters.Text;
      context_params.Values['pattern'] := '';
      context_params.Values['action'] := SimpleAI.Action;
      context_params.Values['intent_name'] := SimpleAI.IntentName;
      context_params.Text := context_params.Text.Replace(#13,'|');
      context_params.Text := context_params.Text.Replace(#10,'|');
      UserData[_AI_CONTEXT] := SimpleAI.SimpleAILib.Intent.Context;
      UserData[_AI_CONTEXT_ACTION] := SimpleAI.Action;
      UserData[_AI_CONTEXT_DATE] := DateTimeToStr(Now);
      UserData[_AI_CONTEXT_PARAM] := context_params.Text;
      context_params.Free;
    end;

    {
    if isAnswer() then
    begin
      // something to do
    end;
    }

  end // if exec
  else
  begin // if not exist in intentDB

    // if answer email
    askIntent := GetSession(_AI_SESSION_ASK_INTENT);
    if askIntent <> '' then
    begin
      if askIntent = _AI_ASK_EMAIL then
      begin
        if isEmail(Message) then
        begin
          UserData['Email'] := Message;
          text_response := GetResponse(askIntent + 'Response', '', '');
          if preg_match('%(Email)%', text_response) then
          begin
            text_response := preg_replace('%(Email)%', Message, text_response, True);
          end;
          Answered;
          SimpleAI.ResponseText.Text := text_response;
        end;
      end;
    end;


    SimpleAI.ResponseText.Text := ErrorHandler(Text);
    if (FOnError <> nil) and (not FisAnswered) then
    begin
      s := FOnError(Text);
      if s <> '' then
        SimpleAI.ResponseText.Text := s;
    end;
  end;

  SimpleAI.ResponseText.Text := StringReplacement(SimpleAI.ResponseText.Text);
  prepareQuestion;

  text_response := SimpleAI.ResponseJson;
  json := TJSONUtil.Create;
  json.LoadFromJsonString(text_response);
  if SimpleAI.Debug then
  begin
    json['response/user/name'] := UserData['Name'];
    json['response/user/fullname'] := UserData['FullName'];
    json['response/user/email'] := UserData['Email'];
    json['response/object/name'] := UserData[_AI_OBJECT];
    s := UserData[_AI_CONTEXT_DATE];
//    --- is not a valid date format
    try
      if MinutesBetween(Now, StrToDateTime(s)) <= CONTEXT_DISCUSSION_MAXTIME then
      begin
        json['response/context/name'] := UserData[_AI_CONTEXT];
        json['response/context/action'] := UserData[_AI_CONTEXT_ACTION];
        json['response/context/datetime'] := UserData[_AI_CONTEXT_DATE];
        json['response/context/params'] := UserData[_AI_CONTEXT_PARAM];
      end;
    except
    end;
    json['response/context/language'] := UserData['language'];
    text_response := json.AsJSONFormated;
  end
  else
    text_response := json.AsJSON;
  json.Free;

  //---
  Result := text_response;
  setSession(_AI_SESSION_MESSAGECOUNT, i2s(messageCount));
  setSession(_AI_SESSION_LASTVISIT, i2s(_GetTickCount));
  UserData[_AI_SESSION_LASTVISIT] := i2s(_GetTickCount);
end;

function TSimpleBotModule.prepareQuestion: boolean;
var
  askIntent: string;
begin
  Result := False;
  askIntent := getSession(_AI_SESSION_ASK_INTENT);
  if askIntent = '' then
    Exit;

  FAskCountdown := s2i(GetSession(_AI_SESSION_ASK_COUNTDOWN)) - 1;
  if SimpleAI.Debug then
    SimpleAI.Parameters.Values[_AI_ASK_COUNTDOWN] := i2s(FAskCountdown);
  if FAskCountdown > 0 then
  begin
    SetSession(_AI_SESSION_ASK_COUNTDOWN, i2s(FAskCountdown));
    Exit;
  end;

  if askIntent = _AI_ASK_EMAIL then
  begin
    if not FAskEmail then
      Exit;
  end;
  EchoQuestions(askIntent);
end;

procedure TSimpleBotModule.SetQuestions(IntentName: string; MsgCount: integer);
begin
  setSession(_AI_SESSION_ASK_INTENT, IntentName);
  SetSession(_AI_SESSION_ASK_COUNTDOWN, i2s(MsgCount));
end;

procedure TSimpleBotModule.ClearQuestions;
begin
  setSession(_AI_SESSION_ASK_INTENT, '');
  SetSession(_AI_SESSION_ASK_COUNTDOWN, '0');
  setSession(_AI_SESSION_ASK_KEY, '');
  setSession(_AI_SESSION_ASK_VAR, '');
end;

procedure TSimpleBotModule.Answered;
begin
  ClearQuestions;
  FisAnswered := True;
end;


function TSimpleBotModule.echoQuestions(IntentName: string; Key: string): string;
begin
  Result := SimpleAI.GetQuestions(IntentName, Key);
  SimpleAI.ResponseText.Add(Result);
  setSession(_AI_SESSION_ASK_INTENT, IntentName);
  setSession(_AI_SESSION_ASK_KEY, SimpleAI.KeyName);
  setSession(_AI_SESSION_ASK_VAR, SimpleAI.VarName);
end;

function TSimpleBotModule.isAnswerOld(): boolean;
var
  askIntent: string;
  askVar, askValue, s: string;
begin
  Result := False;
  askIntent := getSession(_AI_SESSION_ASK_INTENT);
  if askIntent = '' then
    Exit;

  askVar := getSession(_AI_SESSION_ASK_VAR);
  askValue := SimpleAI.Parameters.Values[askVar];
  if askValue = '' then
    Exit;

  setSession(_AI_SESSION_ASK_INTENT, '');
  setSession(_AI_SESSION_ASK_KEY, '');
  setSession(_AI_SESSION_ASK_VAR, '');
  UserData[askVar] := askValue;

  if SimpleAI.Action = _AI_DEFINE then
    Exit;

  // set response
  s := SimpleAI.GetResponse(askIntent + 'Response', '', '');
  if s <> '' then
  begin
    if SimpleAI.SimpleAILib.Intent.Entities.preg_match('%(.*)%', s) then
    begin
      s := StringReplacement(s);
    end;

    SimpleAI.ResponseText.Add(s);
  end;

  Result := True;
end;

function TSimpleBotModule.isMentioned: boolean;
begin
  Result := False;
  if pos('@' + FBotName, Text) > 0 then
    Result := True;
end;

function TSimpleBotModule.isFormula: boolean;
var
  i: integer;
  s: String;
const
  Allowed = ['0'..'9', '+', '-', '/', '*', ' ', '^', '%', '(', ')', '.', ','];
begin
  if Text.IsEmpty then
  begin
    Result := False;
    Exit;
  end;

  s := StringHumanToNominal(Text);
  s := s.Replace('ditambah', '+');
  s := s.Replace('dibagi', '/');
  s := s.Replace('dikali', '*');
  s := s.Replace('dikurangi', '-');
  s := s.Replace('minus', '-');
  s := s.Replace('plus', '+');
  s := s.Replace('tambah', '+');
  s := s.Replace('bagi', '/');
  s := s.Replace('kali', '*');
  s := s.Replace('koma', '.');
  s := s.Replace('nol', '0');
  s := s.Replace('rp.', '');
  s := s.Replace('rp', '');
  s := s.Replace(':', '/');
  s := s.Replace('x', '*');
  s := s.Replace('sama dengan', '');
  s := s.Replace('berapa', '');
  s := s.Replace(',', '.');
  s := s.Replace('?', '');
  s := s.Replace('=', '');
  s := s.Replace(' ', '');
  s := s.Trim;

  Result := True;
  for i:=1 to Length(s) do
  begin
    if not (s[i] in Allowed) then
    begin
      Result := False;
    end;
  end;
end;

function TSimpleBotModule.Formula(AText: string): string;
begin
  SimpleAI.Parameters.Values['Formula_value'] := Text;
  Result := mathHandlerDefault();
end;

function TSimpleBotModule.GetResponse(IntentName: string; Action: string;
  EntitiesKey: string): string;
begin
  Result := SimpleAI.GetResponse(IntentName, Action, EntitiesKey);
  Result := StringReplacement(Result);
end;

function TSimpleBotModule.StringReplacement(Message: string;
  ForceWithSpace: boolean): string;
var
  regex: TRegExpr;
  s: string;
begin
  Result := Message;

  Message := SimpleAI.StringReplacement(Message);

  regex := TRegExpr.Create;
  //regex.Expression := '%(.*)%';
  regex.Expression := '%([a-zA-Z0-9_]+)%';
  if regex.Exec(Message) then
  begin
    s := UserData[regex.Match[1]];
    if ForceWithSpace then
     s := s.Replace('_', ' ').Trim;
    if s <> '' then
      Result := SimpleAI.SimpleAILib.Intent.Entities.preg_replace(
        '%(.*)%', s, Message, True);
    while regex.ExecNext do
    begin
      s := UserData[regex.Match[1]];
      if ForceWithSpace then
       s := s.Replace('_', ' ').Trim;
      if s <> '' then
        Result := SimpleAI.SimpleAILib.Intent.Entities.preg_replace(
          '%(.*)%', s, Message, True);
    end;
  end;
  regex.Free;
end;

procedure TSimpleBotModule.TelegramSend(Token, ChatIDRef, ReplyToMessageID,
  Message: string);
var
  httpClient: THTTPLib;
  httpResponse: IHTTPResponse;
begin
  if Token = '' then
    Exit;
  //if ((ChatIDRef = '') or (ChatIDRef = '0')) then
  //  Exit;

  Message := StringReplace(Message, '\n', #10, [rfReplaceAll]);
  Message := UrlEncode(Message);

  try
    httpClient := THTTPLib.Create;
    httpClient.URL := _TELEGRAM_API_URL + Token + '/sendMessage' +
      '?chat_id=' + ChatIDRef + '&reply_to_message_id=' + ReplyToMessageID +
      '&parse_mode=Markdown' + '&text=' + trim(Message);

    try
      httpResponse := httpClient.Get();
      if httpResponse.ResultCode = 200 then
      begin

      end;
    except
    end;

  finally
    httpClient.Free;
  end;

end;



end.
