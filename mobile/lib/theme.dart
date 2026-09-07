import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const gridBlack = Color(0xFF000000);
const gridGreen = Color(0xFF00FF00);
const gridDim = Color(0xFF007700);
const gridMid = Color(0xFF00AA00);
const gridSoft = Color(0xFF00FF66);
const gridCyan = Color(0xFF00FFD0);
const gridPanel = Color(0xFF021A08);

TextStyle mono({
  Color color = gridGreen,
  double size = 13,
  FontWeight weight = FontWeight.w500,
  FontStyle style = FontStyle.normal,
}) {
  return GoogleFonts.shareTechMono(
    color: color,
    fontSize: size,
    fontWeight: weight,
    fontStyle: style,
    height: 1.25,
  );
}
