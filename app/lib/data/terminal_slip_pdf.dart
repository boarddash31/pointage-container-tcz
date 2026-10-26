import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/terminal_slip.dart';

class TerminalSlipPdf {
  static Future<Uint8List> build(TerminalSlip slip)async{
    final pdf=pw.Document();
    final logo=pw.MemoryImage((await rootBundle.load('assets/brand/marsa-maroc-logo.png')).buffer.asUint8List());
    pw.Widget text(String value,{double size=9})=>pw.Text(value,style:pw.TextStyle(fontSize:size));
    const widths=[42.0,21.0,21.0,76.0,58.0,29.0,21.0,21.0,20.0];
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat.a5,margin:const pw.EdgeInsets.fromLTRB(18,25,18,18),build:(_)=>
      pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
        pw.Padding(padding:const pw.EdgeInsets.only(left:8),child:pw.Align(alignment:pw.Alignment.centerLeft,child:
          pw.SizedBox(width:92,child:pw.Column(children:[pw.Image(logo,width:92),pw.SizedBox(height:2),
            pw.Text('WE LIFT YOUR GROWTH',style:const pw.TextStyle(fontSize:4.8,color:PdfColors.grey600))])))),
        pw.SizedBox(height:15),pw.Center(child:text(slip.title,size:14)),pw.SizedBox(height:15),
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[text('A Check'),text(slip.date),text('Instr .Camion')]),
        pw.SizedBox(height:12),pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
          pw.SizedBox(width:126,child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
            text('Visite :',size:13),pw.SizedBox(height:3),text(slip.visit,size:8),
          ])),
          pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
            text('N° Registration : ${slip.plate}'),pw.SizedBox(height:7),text('CIN Chauffeur : ${slip.cin}'),
          ])),
        ]),pw.SizedBox(height:21),
        pw.Table(tableWidth:pw.TableWidth.min,columnWidths:{for(var i=0;i<widths.length;i++)i:pw.FixedColumnWidth(widths[i])},children:[
          pw.TableRow(children:[for(final column in TerminalSlip.columns)pw.Padding(padding:const pw.EdgeInsets.only(bottom:3),child:text(column))]),
          for(final row in slip.rows)pw.TableRow(children:[for(final value in row)pw.Padding(
            padding:const pw.EdgeInsets.only(right:3,bottom:5),child:text(value,size:8.8))]),
        ]),
        if(slip.references.isNotEmpty)pw.Padding(padding:const pw.EdgeInsets.only(top:8),child:text('Booking / EDO / ERO : ${slip.references.join(' / ')}',size:7.5)),
        pw.SizedBox(height:12),pw.Padding(padding:const pw.EdgeInsets.only(left:20),child:text("L'agent du Terminal : ${slip.agent}",size:10)),
        pw.SizedBox(height:7),pw.Padding(padding:const pw.EdgeInsets.only(right:42),child:pw.Align(alignment:pw.Alignment.centerRight,child:text(slip.date,size:10))),
        pw.SizedBox(height:21),pw.Row(children:List.generate(100,(_)=>pw.Expanded(child:pw.Container(height:.6,color:PdfColors.black,margin:const pw.EdgeInsets.symmetric(horizontal:.5))))),
        pw.SizedBox(height:6),for(final line in TerminalSlip.footer)pw.Padding(padding:const pw.EdgeInsets.only(bottom:2),child:
          pw.Text(line,textAlign:pw.TextAlign.center,style:const pw.TextStyle(fontSize:8))),
      ])));
    return pdf.save();
  }
}
